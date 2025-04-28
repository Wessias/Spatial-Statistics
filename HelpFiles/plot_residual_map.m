function plot_residual_map(regionStates, obs, pred, residual_col, title_text, climRange)
% Plots residuals spatially with consistent colormap and outlines sampled counties
% Inputs:
%   regionStates - shapefile struct for counties
%   obs          - sampled data table (with county_fips)
%   pred         - prediction table (with county_fips and residual_col)
%   residual_col - name of column in pred with residuals
%   title_text   - title for this map
%   climRange    - [min max] range for color scaling

% Setup map axes
ax = usamap({'wisconsin','illinois','iowa'});
set(ax, 'Visible', 'off');

% Define colormap (diverging)
colormap(ax, jet(256));  % You can replace jet with your own diverging colormap
% Get residual min/max from pred table dynamically
resid_values = pred.(residual_col);
resid_min = nanmin(resid_values);
resid_max = nanmax(resid_values);

clim([resid_min, resid_max]); % just for colorbar display
cmap = jet(256);
color_from_resid = @(r) interp1(linspace(resid_min, resid_max, size(cmap,1)), cmap, r, 'linear', 'extrap');


% Precompute FIPS
obs_fips = double(obs.county_fips);
pred_fips = double(pred.county_fips);

for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx = find(pred_fips == fips, 1);
    edge = 'none'; edgeW = 0.1;
    color = [0.85 0.85 0.85];  % default gray

    if any(obs_fips == fips)
        edge = [0.5 0.5 0.5]; edgeW = 1.2;
    end

    if ~isempty(idx)
        resid = pred.(residual_col)(idx);
        if ~isnan(resid)
            color = color_from_resid(resid);
        end
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', edge, ...
        'LineWidth', edgeW);
end

title(title_text);
end
