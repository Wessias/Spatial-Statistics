
function [beta_gls, trend_pred] = fitgls(X_obs, y_obs, coords_obs, X_pred, variogram_model)
% FITGLS estimates trend coefficients using Generalized Least Squares
% Inputs:
%   X_obs          - [n x p] design matrix (including intercept) for observed data
%   y_obs          - [n x 1] response vector
%   coords_obs     - [n x 2] spatial coordinates of observed data
%   X_pred         - [m x p] design matrix for prediction locations
%   variogram_model - struct with fields: range, sill, nugget, func
%
% Outputs:
%   beta_gls       - [p x 1] GLS estimated coefficients
%   trend_pred     - [m x 1] trend prediction at new locations

n = size(X_obs, 1);

% Compute distance matrix
D = squareform(pdist(coords_obs));  % [n x n]

% Build semivariance matrix using variogram model
params = [variogram_model.range, variogram_model.sill];
gamma_fun = @(h) variogram_model.nugget + variogram_model.func(params, h);
Gamma = gamma_fun(D);

% Convert semivariances to covariances
Sigma = variogram_model.sill - Gamma;

% Compute GLS estimator
Sigma_inv = pinv(Sigma);  % robust inversion
beta_gls = (X_obs' * Sigma_inv * X_obs) \ (X_obs' * Sigma_inv * y_obs);

% Predict trend at new locations
trend_pred = X_pred * beta_gls;

end
