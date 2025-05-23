% Read election results
election2024 = readtable('2024_US_County_Level_Presidential_Results.csv');

% Check what columns exist
%head(election2024);

%%

% Load shapefile
counties = readgeotable('cb_2020_us_county_20m.shp');

% Convert GEOID to numeric for matching
counties.FIPS = str2double(counties.GEOID);



%%

% Load election data
election = readtable('election2024_WI_IL_IA.csv');

% Load shapefile (make sure it's unzipped and in your folder, you need all the files)
states = shaperead('cb_2020_us_county_20m.shp', 'UseGeoCoords', true);

% Filter for WI (55), IL (17), IA (19)
state_fps = {'55', '17', '19'};
regionStates = states(ismember({states.STATEFP}, state_fps));

% Preallocate arrays
n = length(regionStates);
centroids = zeros(n, 2); % [Lon, Lat]
geoids = zeros(n, 1);

for i = 1:n
    lon = regionStates(i).Lon;
    lat = regionStates(i).Lat;
    lon = lon(~isnan(lon));  % Remove NaNs
    lat = lat(~isnan(lat));
    centroids(i, :) = [mean(lon), mean(lat)];
    geoids(i) = str2double(regionStates(i).GEOID);
end

% Create table with centroid and vote margin
centroidT = table(geoids, centroids(:,1), centroids(:,2), ...
                  'VariableNames', {'county_fips', 'Lon', 'Lat'});

% Merge with vote margin
merged = innerjoin(election, centroidT, 'Keys', 'county_fips');

popData = readtable("county_population_density_full.csv");

% Ensure county_fips is formatted as a string with leading zeros
merged.county_fips = string(merged.county_fips);
popData.county_fips = string(popData.county_fips);

popDensityOnly = popData(:, {'county_fips', 'pop_density'});


% Join on county_fips
merged = innerjoin(merged, popDensityOnly, "Keys", "county_fips", "RightVariables","pop_density");

% Load the covariate data
covData = readtable('county_covariates_final.csv');

% Make sure FIPS codes are strings
merged.county_fips = string(merged.county_fips);
covData.FIPS = string(covData.FIPS);

% Perform inner join to keep only matching counties
merged = innerjoin(merged, covData, 'LeftKeys', 'county_fips', 'RightKeys', 'FIPS');



merged.county_fips = double(merged.county_fips);

%% START WITH THE KRIGING

rng(42); % reproducible
percentile = 0.2;
n = height(merged);
idx_sample = randperm(n, round(percentile * n));
obs = merged(idx_sample, :);
pred = merged(setdiff(1:n, idx_sample), :);

coords_obs = [obs.Lon, obs.Lat];
values_obs = obs.per_point_diff;

% Compute empirical variogram
vstruct = variogram(coords_obs, values_obs, 'nrbins', 15);

d = vstruct.distance;
gamma = vstruct.val;


% Fit spherical model
[a,c,n,model] = variogramfit(d, gamma, max(d)/2, var(values_obs), [], 'model', 'gaussian');

%Nugget gives [] sometimes
if isempty(model.nugget)
    model.nugget = min(model.gamma - model.gammahat);  % estimate from fit residuals
end


coords_pred = [pred.Lon, pred.Lat];

% Run Kriging
Zhat = ordinary_kriging_manual(coords_obs, values_obs, coords_pred, model);

% Save predictions
pred.ok_pred = Zhat;

rmse_ok = sqrt(mean((pred.ok_pred - pred.per_point_diff).^2));
fprintf('Ordinary Kriging RMSE (Gaussian): %.2f\n', rmse_ok);

%% Plot Ordinary Kriging (fast)

% Custom blue-to-black-to-red colormap
n = 256;
half = floor(n / 2);

% Blue to black
blue_black = [linspace(0, 0, half)', linspace(0, 0, half)', linspace(1, 0, half)'];

% Black to red
black_red = [linspace(0, 1, half)', linspace(0, 0, half)', linspace(0, 0, half)'];

% Combine into one map
custom_cmap = [blue_black; black_red];


% Define the region of interest
lon_range = linspace(min(merged.Lon), max(merged.Lon), 100);
lat_range = linspace(min(merged.Lat), max(merged.Lat), 100);
[LonGrid, LatGrid] = meshgrid(lon_range, lat_range);



% Convert to [n x 2] coordinate list
grid_coords = [LonGrid(:), LatGrid(:)];

% Predict vote margins across the grid
Zgrid = ordinary_kriging_manual(coords_obs, values_obs, grid_coords, model);

% Reshape to match the grid
Zgrid = reshape(Zgrid, size(LonGrid));

% Plot interpolated surface
figure;
contourf(LonGrid, LatGrid, Zgrid, 50, 'LineColor', 'none');
colormap(custom_cmap);
colorbar;
clim([-1 1]);  % lock color scale to vote margin range
hold on;

% Overlay observed points
scatter(obs.Lon, obs.Lat, 40, obs.per_point_diff, 'filled', ...
        'MarkerEdgeColor', 'k');
title('Ordinary Kriging: Vote Margin');
xlabel('Longitude'); ylabel('Latitude');
axis equal;



%
%variogramfit(d, gamma, max(d)/2, var(values_obs), 0, 'model', 'spherical');
%variogramfit(d, gamma, max(d)/2, var(values_obs), 0, 'model', 'gaussian');
%variogramfit(d, gamma, max(d)/2, var(values_obs), 0, 'model', 'exponential');
%legend('Empirical')


%% Ordinary kriging plotting (slow with borders and stuff)
figure;
ax = usamap({'wisconsin', 'illinois', 'iowa'});
set(ax, 'Visible', 'off');

% Custom colormap: red to black to blue
ncolors = 256;
half = floor(ncolors / 2);
blue_black = [linspace(0, 0, half)', linspace(0, 0, half)', linspace(1, 0, half)'];
black_red = [linspace(0, 1, half)', linspace(0, 0, half)', linspace(0, 0, half)'];
custom_cmap = [blue_black; black_red];
colormap(ax, custom_cmap);
clim([-1, 1]);
colorbar;

% Loop through counties
for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);

    % Check if county was sampled (in obs) or predicted (in pred)
    idx_obs = find(obs.county_fips == fips);
    idx_pred = find(pred.county_fips == fips);

    % Default
    color = [0.85, 0.85, 0.85];
    edge = 'none';
    edgeW = 0.1;

    if ~isempty(idx_obs)
        % Sampled: use actual observed margin
        margin = obs.per_point_diff(idx_obs);
        % Soft contrast for small margins using sqrt scaling
        scaled_margin = sign(margin) .* sqrt(abs(margin));

% Clamp to [-1, 1] in case sqrt made it small
        scaled_margin = max(min(scaled_margin, 1), -1);
        edge = [0.5, 0.5, 0.5];
        edgeW = 1;
    elseif ~isempty(idx_pred)
        % Not sampled: use predicted margin
        margin = pred.ok_pred(idx_pred);
        % Soft contrast for small margins using sqrt scaling
        scaled_margin = sign(margin) .* sqrt(abs(margin));

% Clamp to [-1, 1] in case sqrt made it small
        scaled_margin = max(min(scaled_margin, 1), -1);
    else
        margin = NaN;
    end

    % Assign color based on margin
    if isnan(scaled_margin)
        color = [0.85, 0.85, 0.85];
    elseif margin > 0
        color = [1, 0, 0] * min(scaled_margin, 1);
    elseif margin < 0
        color = [0, 0, 1] * min(abs(scaled_margin), 1);
    else
        color = [0, 0, 0];
    end

    % Plot county
    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end


title('Kriging Predicted Margins with Observed Counties (True Values)');

%% Ordinary Kriging vs real values plot (y=x)

figure;
scatter(pred.per_point_diff, pred.ok_pred, 60, 'filled');
xlabel('True Vote Margin');
ylabel('Kriging Predicted Vote Margin');
title('Ordinary Kriging: Predicted vs Actual Margins');
grid on;
axis equal;
xlim([-1 1]);
ylim([-1 1]);
refline(1, 0);  % 1:1 line


%% Ordinary kriging vs real margins, map side by side
% Create figure with 2 subplots
figure;
tiledlayout(1,2, 'Padding', 'compact', 'TileSpacing', 'compact');

% Custom red-black-blue colormap
ncolors = 256;
half = floor(ncolors / 2);
blue_black = [linspace(0, 0, half)', linspace(0, 0, half)', linspace(1, 0, half)'];
black_red = [linspace(0, 1, half)', linspace(0, 0, half)', linspace(0, 0, half)'];
custom_cmap = [blue_black; black_red];

% ========== 1. TRUE MARGINS ==========
nexttile;
ax1 = usamap({'wisconsin','illinois','iowa'});
set(ax1, 'Visible', 'off');
colormap(ax1, custom_cmap);
clim([-1 1]);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx = find(election.county_fips == fips);

    color = [0.85 0.85 0.85];
    edge = 'none';
    edgeW = 0.1;

    if ~isempty(idx)
        margin = election.per_point_diff(idx);
        scaled_margin = sign(margin) .* sqrt(abs(margin));

% Clamp to [-1, 1] in case sqrt made it small
        scaled_margin = max(min(scaled_margin, 1), -1);
        
        if ~isnan(scaled_margin)
            if scaled_margin > 0
                color = [1, 0, 0] * min(scaled_margin, 1);
            elseif scaled_margin < 0
                color = [0, 0, 1] * min(abs(scaled_margin), 1);
            else
                color = [0, 0, 0];
            end
        end
    end

    % Show outline for sampled counties
    if any(obs.county_fips == fips)
        edge = [0.5 0.5 0.5];
        edgeW = 1.2;
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
title('Actual Vote Margins (Sampled Counties Outlined)');

% ========== 2. KRIGED MARGINS ==========
nexttile;
ax2 = usamap({'wisconsin','illinois','iowa'});
set(ax2, 'Visible', 'off');
colormap(ax2, custom_cmap);
clim([-1 1]);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx_obs = find(obs.county_fips == fips);
    idx_pred = find(pred.county_fips == fips);

    color = [0.85 0.85 0.85];
    edge = 'none';
    edgeW = 0.1;

    if ~isempty(idx_obs)
        margin = obs.per_point_diff(idx_obs);
        scaled_margin = sign(margin) .* sqrt(abs(margin));

% Clamp to [-1, 1] in case sqrt made it small
        scaled_margin = max(min(scaled_margin, 1), -1);
        edge = [0.5, 0.5, 0.5];
        edgeW = 1.2;
    elseif ~isempty(idx_pred)
        margin = pred.ok_pred(idx_pred);
        scaled_margin = sign(margin) .* sqrt(abs(margin));

% Clamp to [-1, 1] in case sqrt made it small
        scaled_margin = max(min(scaled_margin, 1), -1);
    else
        scaled_margin = NaN;
    end

    if ~isnan(scaled_margin)
        if scaled_margin > 0
            color = [1, 0, 0] * min(scaled_margin, 1);
        elseif margin < 0
            color = [0, 0, 1] * min(abs(scaled_margin), 1);
        else
            color = [0, 0, 0];
        end
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
title('Ordinary Kriging Predicted Margins');


%%
% Side-by-side map of actual vs kriged margins
figure;
tiledlayout(1,2, 'Padding', 'compact', 'TileSpacing', 'compact');

% Choose a colormap (try redbluecmap from File Exchange or any built-in one)
% colormapName = redbluecmap(256); % if installed
colormapName = jet(256); % or parula, coolwarm, turbo (R2023b+)
climRange = [-1 1];

% ===== 1. ACTUAL VOTE MARGINS =====
nexttile;
ax1 = usamap({'wisconsin','illinois','iowa'});
set(ax1, 'Visible', 'off');
colormap(ax1, colormapName);
caxis(climRange);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx = find(election.county_fips == fips);

    color = [0.85 0.85 0.85]; % default
    edge = 'none';
    edgeW = 0.1;

    if ~isempty(idx)
        margin = election.per_point_diff(idx);
        if ~isnan(margin)
            color = interp1(linspace(climRange(1), climRange(2), size(colormapName,1)), ...
                            colormapName, margin, 'linear', 'extrap');
        end
    end

    if any(obs.county_fips == fips)
        edge = [0.5 0.5 0.5];
        edgeW = 1.2;
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
title('Actual Vote Margins');

% ===== 2. ORDINARY KRIGING MARGINS =====
nexttile;
ax2 = usamap({'wisconsin','illinois','iowa'});
set(ax2, 'Visible', 'off');
colormap(ax2, colormapName);
caxis(climRange);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx_obs = find(obs.county_fips == fips);
    idx_pred = find(pred.county_fips == fips);

    color = [0.85 0.85 0.85]; % default
    edge = 'none';
    edgeW = 0.1;

    if ~isempty(idx_obs)
        margin = obs.per_point_diff(idx_obs);
        edge = [0.5 0.5 0.5];
        edgeW = 1.2;
    elseif ~isempty(idx_pred)
        margin = pred.ok_pred(idx_pred);
    else
        margin = NaN;
    end

    if ~isnan(margin)
        color = interp1(linspace(climRange(1), climRange(2), size(colormapName,1)), ...
                        colormapName, margin, 'linear', 'extrap');
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
colorbar;
title('Ordinary Kriging Predicted Margins');











%% Universal Kriging using only position

%Linear regression to fit trend parameters for 
% Z(s) = beta_0 + beta_1 *Lon(s) + beta_2 * Lat(s) + eps(s)

X_obs = [obs.Lon, obs.Lat];  % Predictors
y_obs = obs.per_point_diff;  % Target

trend_model = fitlm(X_obs, y_obs);

X_pred = [pred.Lon, pred.Lat];
trend_pred = predict(trend_model, X_pred);

residuals_obs = y_obs - predict(trend_model, X_obs);

% Compute variogram of residuals
vstruct = variogram(X_obs, residuals_obs, 'nrbins', 15);
d = vstruct.distance;
gamma = vstruct.val;

% Fit variogram model (e.g., Gaussian)
[~, ~, ~, model] = variogramfit(d, gamma, max(d)/2, var(residuals_obs), [], 'model', 'gaussian');
if isempty(model.nugget)
    model.nugget = 0.001;  % fallback
end

Zresid_pred = ordinary_kriging_manual(X_obs, residuals_obs, X_pred, model);

Zuk_pred = trend_pred + Zresid_pred;
pred.uk_pred = Zuk_pred;

rmse_uk = sqrt(mean((pred.per_point_diff - pred.uk_pred).^2));
fprintf('Universal Kriging RMSE: %.3f\n', rmse_uk);



%% 
% Create figure with 3 subplots
figure;
tiledlayout(1,3, 'Padding', 'compact', 'TileSpacing', 'compact');

% Colormap settings
colormapName = jet(256); % or any preferred MATLAB colormap
climRange = [-1, 1];

% ============================
% 1. TRUE MARGINS
% ============================
nexttile;
ax1 = usamap({'wisconsin','illinois','iowa'});
set(ax1, 'Visible', 'off');
colormap(ax1, colormapName);
caxis(climRange);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx = find(election.county_fips == fips);

    color = [0.85 0.85 0.85];
    edge = 'none'; edgeW = 0.1;

    if ~isempty(idx)
        margin = election.per_point_diff(idx);
        if ~isnan(margin)
            color = interp1(linspace(climRange(1), climRange(2), size(colormapName,1)), ...
                            colormapName, margin, 'linear', 'extrap');
        end
    end

    if any(obs.county_fips == fips)
        edge = [0.5 0.5 0.5];
        edgeW = 1.2;
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
title('Actual Vote Margins');

% ============================
% 2. ORDINARY KRIGING
% ============================
nexttile;
ax2 = usamap({'wisconsin','illinois','iowa'});
set(ax2, 'Visible', 'off');
colormap(ax2, colormapName);
caxis(climRange);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx_obs = find(obs.county_fips == fips);
    idx_pred = find(pred.county_fips == fips);

    color = [0.85 0.85 0.85]; edge = 'none'; edgeW = 0.1;

    if ~isempty(idx_obs)
        margin = obs.per_point_diff(idx_obs);
        edge = [0.5 0.5 0.5]; edgeW = 1.2;
    elseif ~isempty(idx_pred)
        margin = pred.ok_pred(idx_pred);
    else
        margin = NaN;
    end

    if ~isnan(margin)
        color = interp1(linspace(climRange(1), climRange(2), size(colormapName,1)), ...
                        colormapName, margin, 'linear', 'extrap');
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
title('Ordinary Kriging Prediction');

% ============================
% 3. UNIVERSAL KRIGING
% ============================
nexttile;
ax3 = usamap({'wisconsin','illinois','iowa'});
set(ax3, 'Visible', 'off');
colormap(ax3, colormapName);
caxis(climRange);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx_obs = find(obs.county_fips == fips);
    idx_pred = find(pred.county_fips == fips);

    color = [0.85 0.85 0.85]; edge = 'none'; edgeW = 0.1;

    if ~isempty(idx_obs)
        margin = obs.per_point_diff(idx_obs);  % Show true for sampled
        edge = [0.5 0.5 0.5]; edgeW = 1.2;
    elseif ~isempty(idx_pred)
        margin = pred.uk_pred(idx_pred);       % Show predicted for others
    else
        margin = NaN;
    end

    if ~isnan(margin)
        color = interp1(linspace(climRange(1), climRange(2), size(colormapName,1)), ...
                        colormapName, margin, 'linear', 'extrap');
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end
colorbar;
title('Universal Kriging Prediction');


%%


figure;
hold on;
scatter(pred.per_point_diff, pred.cov_pred, 60, 'filled');
scatter(pred.per_point_diff, pred.cov_opt_pred, 60);
hold off;
xlabel('True Vote Margin');
ylabel('Kriging Predicted Vote Margin');
title('Cov and Opt Cov: Predicted vs Actual Margins');
grid on;
axis equal;
xlim([-1 1]);
ylim([-1 1]);
refline(1, 0);  % 1:1 line












%% Universal kriging using position and population density

X_obs = [obs.Lon, obs.Lat, obs.pop_density];
y_obs = obs.per_point_diff;

trend_model = fitlm(X_obs, y_obs);

X_pred = [pred.Lon, pred.Lat, pred.pop_density];
trend_pred = predict(trend_model, X_pred);

residuals_obs = y_obs - predict(trend_model, X_obs);


vstruct = variogram(X_obs(:,1:2), residuals_obs, 'nrbins', 15);
d = vstruct.distance;
gamma = vstruct.val;

[~, ~, ~, model] = variogramfit(d, gamma, max(d)/2, var(residuals_obs), [], 'model', 'gaussian');
if isempty(model.nugget), model.nugget = 0.001; end


Zresid_pred = ordinary_kriging_manual(X_obs(:,1:2), residuals_obs, X_pred(:,1:2), model);


Zuk_pred = trend_pred + Zresid_pred;
pred.uk_pred = Zuk_pred;

rmse_uk = sqrt(mean((pred.per_point_diff - pred.uk_pred).^2));
fprintf('Universal Kriging RMSE (with pop_density): %.3f\n', rmse_uk);

%%

%% Universal kriging using position and population density

X_obs = [obs.Lon, obs.Lat, obs.pop_density];
y_obs = obs.per_point_diff;

trend_model = fitlm(X_obs, y_obs);

X_pred = [pred.Lon, pred.Lat, pred.pop_density];
trend_pred = predict(trend_model, X_pred);

residuals_obs = y_obs - predict(trend_model, X_obs);


vstruct = variogram(X_obs(:,1:2), residuals_obs, 'nrbins', 15);
d = vstruct.distance;
gamma = vstruct.val;

[~, ~, ~, model] = variogramfit(d, gamma, max(d)/2, var(residuals_obs), [], 'model', 'gaussian');
if isempty(model.nugget), model.nugget = 0.001; end


Zresid_pred = ordinary_kriging_manual(X_obs(:,1:2), residuals_obs, X_pred(:,1:2), model);


Zuk_pred = trend_pred + Zresid_pred;
pred.uk_pred = Zuk_pred;

rmse_uk = sqrt(mean((pred.per_point_diff - pred.uk_pred).^2));
fprintf('Universal Kriging RMSE (with pop_density): %.3f\n', rmse_uk);



%% ALEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEX
% BELOW IS CODE TO TEST WITH DIFFERENT COVARIATES

%% Universal Kriging with covariates
% Double check with column names in merged
%covariates_to_use = {'pop_density', 'Some_College', 'Unemployment', 'VoterTurnout', 'Child_Care_Cost_Burden','Severe_Housing_Cost_Burden', 'High_School_Grad'};
covariates_to_use = {'pop_density', 'Some_College', 'Severe_Housing_Cost_Burden', 'Unemployment', 'VoterTurnout', 'High_School_Grad'};
predCov = full_kriging_model(merged, obs, pred, covariates_to_use, true, model); % with GLS
%predCov = full_kriging_model(merged, obs, pred, covariates_to_use, false, model); % with OLS (fitlm)

% True margins vs predicted margins
true_vals = predCov.per_point_diff;
pred_vals = predCov.kriging_pred;

pred.cov_opt_pred = pred_vals;
%pred.cov_pred = pred_vals;

% Calculate RMSE
rmse_final = sqrt(mean((true_vals - pred_vals).^2, 'omitnan'));

fprintf('Full Model RMSE: %.4f\n', rmse_final);



%% Plot universal kriging with covariates
% Create a side-by-side layout
figure;
t = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

% Plot true margins
nexttile;
plot_margin_map(regionStates, election, obs, pred, 'per_point_diff', 'True Vote Margins');
caxis([-1,1]);

% Plot full kriging prediction
nexttile;
plot_margin_map(regionStates, election, obs, pred, 'kriging_pred', 'Full Model Kriging Prediction');
caxis([-1,1]);

colorbar;


%% Kriging with external drift

X_all = [merged.Lon, merged.Lat, merged.pop_density];
y_all = merged.per_point_diff;

% Fit global trend model using all known data
ked_trend_model = fitlm(X_all, y_all);

X_obs = [obs.Lon, obs.Lat, obs.pop_density];
residuals_obs = obs.per_point_diff - predict(ked_trend_model, X_obs);

X_pred = [pred.Lon, pred.Lat, pred.pop_density];
ked_trend_pred = predict(ked_trend_model, X_pred);

vstruct = variogram(X_obs(:,1:2), residuals_obs, 'nrbins', 15);
d = vstruct.distance;
gamma = vstruct.val;

[~, ~, ~, ked_model] = variogramfit(d, gamma, max(d)/2, var(residuals_obs), [], 'model', 'gaussian');
if isempty(ked_model.nugget), ked_model.nugget = 0.001; end

Zresid_ked = ordinary_kriging_manual(X_obs(:,1:2), residuals_obs, X_pred(:,1:2), ked_model);

pred.ked_pred = ked_trend_pred + Zresid_ked;

rmse_ked = sqrt(mean((pred.per_point_diff - pred.ked_pred).^2));
fprintf('Kriging with External Drift RMSE: %.3f\n', rmse_ked);

%% Kriging but estimating trend with gls
% 1. Prepare inputs
X_obs = [ones(height(obs),1), obs.Lon, obs.Lat, obs.pop_density];
y_obs = obs.per_point_diff;
coords_obs = [obs.Lon, obs.Lat];

X_pred = [ones(height(pred),1), pred.Lon, pred.Lat, pred.pop_density];

% 2. Use your previously fitted variogram model (e.g., from residuals)
[beta_gls, trend_gls_pred] = fitgls(X_obs, y_obs, coords_obs, X_pred, model);

% 3. Continue with residual kriging as before
residuals_gls = y_obs - X_obs * beta_gls;
Zresid_gls = ordinary_kriging_manual(coords_obs, residuals_gls, [pred.Lon, pred.Lat], model);

% 4. Final prediction
pred.gls_pred = trend_gls_pred + Zresid_gls;

%%
methods = {'ok_pred', 'uk_pred', 'ked_pred', 'gls_pred', 'kriging_pred'};
for i = 1:length(methods)
    rmse = sqrt(mean((pred.per_point_diff - pred.(methods{i})).^2));
    fprintf('%s RMSE: %.3f\n', methods{i}, rmse);
end



%%

figure;
tiledlayout(1, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile; plot_margin_map(regionStates, election, obs, pred, 'per_point_diff', 'Actual');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'ok_pred', 'Ordinary Kriging');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'uk_pred', 'Universal Kriging');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'ked_pred', 'Kriging w/ External Drift');


%%

figure;
tiledlayout(1, 5, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile; plot_margin_map(regionStates, election, obs, pred, 'per_point_diff', 'Real');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'ok_pred', 'OK');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'uk_pred', 'UK - Spatial Trend');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'cov_pred', 'UK - Spatial + All Thematic');
nexttile; plot_margin_map(regionStates, election, obs, pred, 'cov_opt_pred', 'UK - Forward Selection');
colorbar;

%%
figure;
t = tiledlayout(2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

% Top Row - Single Central Tile for Real Margins
ax1 = nexttile([1, 4]); 
plot_margin_map(regionStates, election, obs, pred, 'per_point_diff', 'Real Margins');

% Bottom Row - 4 Prediction Models
ax2 = nexttile; plot_margin_map(regionStates, election, obs, pred, 'ok_pred', 'OK');
ax3 = nexttile; plot_margin_map(regionStates, election, obs, pred, 'uk_pred', 'UK - Spatial');
ax4 = nexttile; plot_margin_map(regionStates, election, obs, pred, 'cov_pred', 'UK - Spatial + All Thematic');
ax5 = nexttile; plot_margin_map(regionStates, election, obs, pred, 'cov_opt_pred', 'UK - Forward Selection');

% Shared colorbar linked to the last axis
cb = colorbar(ax1);
cb.Label.String = 'Vote Margin (Republican - Democratic)';
cb.Limits = [-1, 1];





%%

pred.ok_resid  = pred.per_point_diff - pred.ok_pred;
pred.uk_resid  = pred.per_point_diff - pred.uk_pred;
%pred.ked_resid = pred.per_point_diff - pred.ked_pred;
%pred.gls_resid = pred.per_point_diff - pred.gls_pred;
pred.cov_opt_resid = pred.per_point_diff - pred.cov_opt_pred;
pred.cov_resid = pred.per_point_diff - pred.cov_pred;
%%
figure;
t = tiledlayout(1,5, 'Padding', 'compact', 'TileSpacing', 'compact');

climRange = [-0.5, 0.5];

nexttile; plot_residual_map(regionStates, obs, pred, 'ok_resid', 'OK Residuals', climRange);
nexttile; plot_residual_map(regionStates, obs, pred, 'uk_resid', 'UK Residuals', climRange);
nexttile; plot_residual_map(regionStates, obs, pred, 'ked_resid', 'KED Residuals', climRange);
nexttile; plot_residual_map(regionStates, obs, pred, 'gls_resid', 'GLSK Residuals', climRange);
nexttile; plot_residual_map(regionStates, obs, pred, 'cov_resid', 'Cov UK Residuals', climRange);

% Add shared colorbar
colorbar;



%%
% Choose which residuals to analyze
resid_name = 'cov_opt_resid';  % <-- Change this to uk_resid, ked_resid, gls_resid

resid_values = pred.(resid_name);
coords_pred = [pred.Lon, pred.Lat];  % prediction coordinates

% Remove NaNs
valid = ~isnan(resid_values);
resid_values = resid_values(valid);
coords_pred = coords_pred(valid, :);

%% 1. Histogram
figure;
histogram(resid_values, 'Normalization', 'pdf', 'BinWidth', 0.05);
xlabel('Residual (Actual - Predicted)');
ylabel('Density');
title(sprintf('Histogram of Residuals (Optimal Covariate Model)', strrep(resid_name, '_', '\_')));
grid on;

%% 2. Mean and Std
mean_resid = mean(resid_values);
std_resid = std(resid_values);

fprintf('Mean Residual (%s): %.4f\n', resid_name, mean_resid);
fprintf('Std Dev of Residual (%s): %.4f\n', resid_name, std_resid);

%% 3. Variogram of Residuals
vstruct = variogram(coords_pred, resid_values, 'nrbins', 15);

figure;
plot(vstruct.distance, vstruct.val, 'o-');
xlabel('Distance');
ylabel('Semivariance');
title(sprintf('Variogram of Residuals (Full Covariate Model)', strrep(resid_name, '_', '\_')));
grid on;


%%
% Set up models to compare
methods = {'ok_resid', 'uk_resid', 'cov_resid', 'cov_opt_resid'};
labels = {'OK', 'UK - Spatial Trend', 'UK - Spatial + All Thematic', 'UK - Forward Selection'};
colors = lines(length(methods));  % distinct colors

figure;
hold on;

for i = 1:length(methods)
    % Extract residuals
    resid_values = pred.(methods{i});
    coords_pred = [pred.Lon, pred.Lat];

    % Remove NaNs
    valid = ~isnan(resid_values);
    resid_values = resid_values(valid);
    coords_pred = coords_pred(valid, :);

    % Compute empirical variogram
    vstruct = variogram(coords_pred, resid_values, 'nrbins', 15);

    % Plot
    plot(vstruct.distance, vstruct.val, 'o-', 'Color', colors(i,:), 'DisplayName', labels{i});
end

xlabel('Distance');
ylabel('Semivariance');
title('Comparison of Residual Variograms');
legend('Location', 'northwest');
grid on;
hold off;









%%




% Set up the map (bounds can be adjusted)
figure;
ax = usamap({'wisconsin', 'illinois', 'iowa'});
set(ax, 'Visible', 'off');

% Loop through each county and color based on margin
for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx = find(election.county_fips == fips);

    % Default gray color
    color = [0.85 0.85 0.85];

    if ~isempty(idx)
        margin = election.per_point_diff(idx);

        if isnan(margin)
            color = [0.85 0.85 0.85]; % neutral
        elseif margin > 0
            % GOP win (red, intensity based on margin)
            color = [1, 0.2, 0.2] * min(margin, 1);
        else
            % Dem win (blue, intensity based on margin)
            color = [0.2, 0.2, 1] * min(abs(margin), 1);
        end
    end

    % Draw county with selected color
    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', 'none');
end

title('2024 Presidential Election Vote Margins by County - WI, IL, IA');