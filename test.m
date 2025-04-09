% Read election results
election2024 = readtable('2024_US_County_Level_Presidential_Results.csv');

% Check what columns exist
head(election2024)

%%

% Load shapefile
counties = readgeotable('cb_2020_us_county_20m.shp');

% Convert GEOID to numeric for matching
counties.FIPS = str2double(counties.GEOID);

%%
% Load election data
election = readtable('election2024_simplified.csv');

% Load shapefile (download and unzip if needed)
states = shaperead('cb_2020_us_county_20m.shp', 'UseGeoCoords', true);

% Create the map
figure;
ax = usamap('all');
set(ax, 'Visible', 'off');

% Loop through each county
for i = 1:length(states)
    fips = str2double(states(i).GEOID);
    idx = find(election.county_fips == fips);

    % Default color = gray
    color = [0.85 0.85 0.85];

    if ~isempty(idx)
        margin = election.per_point_diff(idx);

        if isnan(margin)
            color = [0.85 0.85 0.85]; % gray
        elseif margin > 0
            % Red for GOP win
            color = [1, 0.2, 0.2] * min(margin, 1);
        else
            % Blue for Dem win
            color = [0.2, 0.2, 1] * min(abs(margin), 1);
        end
    end

    % Draw the county with assigned color
    geoshow(states(i).Lat, states(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', 'none');
end

title('2024 Presidential Election Results by County');


%%


% Load election data (Texas only)
election = readtable('election2024_simplified.csv');
txFIPS = election.county_fips(election.county_fips >= 48000 & election.county_fips < 49000);
electionTX = election(ismember(election.county_fips, txFIPS), :);

% Load shapefile and filter for Texas (STATEFP == '48')
states = shaperead('cb_2020_us_county_20m.shp', 'UseGeoCoords', true);
statesTX = states(strcmp({states.STATEFP}, '48'));

% Create the map
figure;
ax = usamap('texas');
set(ax, 'Visible', 'off');

% Loop through each Texas county
for i = 1:length(statesTX)
    fips = str2double(statesTX(i).GEOID);
    idx = find(electionTX.county_fips == fips);

    % Default color = gray
    color = [0.85 0.85 0.85];

    if ~isempty(idx)
        margin = electionTX.per_point_diff(idx);

        if isnan(margin)
            color = [0.85 0.85 0.85]; % gray
        elseif margin > 0
            % Red for GOP win
            color = [1, 0.2, 0.2] * min(margin, 1);
        else
            % Blue for Dem win
            color = [0.2, 0.2, 1] * min(abs(margin), 1);
        end
    end

    % Draw the county with assigned color
    geoshow(statesTX(i).Lat, statesTX(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', 'none');
end

title('2024 Presidential Vote Margins by County - Texas');


%%

% Load election data
election = readtable('election2024_WI_IL_IA.csv');

% Load shapefile (make sure it's unzipped and in your folder)
states = shaperead('cb_2020_us_county_20m.shp', 'UseGeoCoords', true);

% Filter for WI (55), IL (17), IA (19)
state_fps = {'55', '17', '19'};
regionStates = states(ismember({states.STATEFP}, state_fps));

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


%%

% Load election data
election = readtable('election2024_WI_IL_IA.csv');

% Load shapefile (national counties)
allStates = shaperead('cb_2020_us_county_20m.shp', 'UseGeoCoords', true);

% Filter for WI (55), IL (17), IA (19)
state_fps = {'55', '17', '19'};
regionStates = allStates(ismember({allStates.STATEFP}, state_fps));

% Create the map
figure;
ax = usamap({'wisconsin', 'illinois', 'iowa'});
set(ax, 'Visible', 'off');

% Loop through each county and assign fixed colors
for i = 1:length(regionStates)
    fips = str2double(regionStates(i).GEOID);
    idx = find(election.county_fips == fips, 1);

    % Default gray
    color = [0.85 0.85 0.85];

    if ~isempty(idx)
        if election.per_point_diff(idx) > 0
            color = [1, 0, 0]; % Red = Republican win
        elseif election.per_point_diff(idx) < 0
            color = [0, 0, 1]; % Blue = Democrat win
        end
    end

    geoshow(regionStates(i).Lat, regionStates(i).Lon, ...
        'DisplayType', 'polygon', ...
        'FaceColor', color, ...
        'EdgeColor', 'none');
end

title('2024 Election Result by County – WI, IL, IA (Fixed Colors)');
