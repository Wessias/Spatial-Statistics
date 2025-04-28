function plot_margin_map(regionStates, election, obs, pred, pred_var, title_text)
% Plots county-level vote margins, using true values for sampled counties
% and predictions for the rest.
%
% Inputs:
% - regionStates: struct array of counties (from shaperead)
% - election: table with county_fips and true per_point_diff
% - obs: sampled counties (table with county_fips and per_point_diff)
% - pred: predicted counties (table with county_fips and prediction columns)
% - pred_var: string name of column in pred to use (e.g. 'ok_pred')
% - title_text: title of the map

% Set up map
ax = usamap({'wisconsin','illinois','iowa'});
set(ax, 'Visible', 'off');

% Colormap and limits
colormap(jet(256));
caxis([-1 1]);
color_from_margin = @(m) interp1(linspace(-1, 1, 256), jet(256), m, 'linear', 'extrap');

% Pre-convert FIPS
obs_fips = double(obs.county_fips);
pred_fips = double(pred.county_fips);
election_fips = double(election.county_fips);

% Loop through counties
for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    margin = NaN;

    % Get true margin if in observed sample
    if any(obs_fips == fips)
        margin = obs.per_point_diff(obs_fips == fips);
        edge = [0.5, 0.5, 0.5];
        edgeW = 1.2;

    % Else get predicted margin
    elseif any(pred_fips == fips)
        idx = find(pred_fips == fips, 1);
        margin = pred.(pred_var)(idx);
        edge = 'none';
        edgeW = 0.1;

    % Or fallback to election data (for "truth" map)
    elseif any(election_fips == fips)
        margin = election.per_point_diff(election_fips == fips);
        edge = 'none';
        edgeW = 0.1;

    else
        margin = NaN;
        edge = 'none';
        edgeW = 0.1;
    end

    % Assign color
    if isnan(margin)
        color = [0.85 0.85 0.85];
    else
        color = color_from_margin(margin);
    end

    % Plot polygon
    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end

title(title_text);
end
