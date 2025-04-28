
function pred = full_kriging_model(merged, obs, pred, covariate_list, use_gls, variogram_model)
% FULL_KRIGING_MODEL fits trend + kriges residuals in one step
%
% Inputs:
%   merged          - Full dataset (with all covariates)
%   obs             - Sampled observed data
%   pred            - Prediction points
%   covariate_list  - Cell array of covariate names to include
%   use_gls         - true/false, whether to use GLS instead of OLS
%   variogram_model - fitted variogram model struct (for residuals)
%
% Output:
%   pred            - updated prediction table with pred.kriging_pred

% Build design matrices (always include intercept, Lon, Lat)
X_obs = [ones(height(obs),1), obs.Lon, obs.Lat];
X_pred = [ones(height(pred),1), pred.Lon, pred.Lat];

for i = 1:length(covariate_list)
    varname = covariate_list{i};
    X_obs = [X_obs, obs.(varname)];
    X_pred = [X_pred, pred.(varname)];
end

y_obs = obs.per_point_diff;

coords_obs = [obs.Lon, obs.Lat];
coords_pred = [pred.Lon, pred.Lat];

if use_gls
    % Use GLS to fit trend
    [beta_gls, trend_pred] = fitgls(X_obs, y_obs, coords_obs, X_pred, variogram_model);
    trend_obs = X_obs * beta_gls;
else
    % Use OLS (fitlm)
    trend_model = fitlm(X_obs(:,2:end), y_obs);
    trend_obs = predict(trend_model, X_obs(:,2:end));
    trend_pred = predict(trend_model, X_pred(:,2:end));
end

% Residuals at observed points
residuals_obs = y_obs - trend_obs;

% Krige the residuals
Zresid_pred = ordinary_kriging_manual(coords_obs, residuals_obs, coords_pred, variogram_model);

% Final prediction = trend + kriged residual
pred.kriging_pred = trend_pred + Zresid_pred;

end
