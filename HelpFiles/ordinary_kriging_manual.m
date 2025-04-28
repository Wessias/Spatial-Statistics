
function Zhat = ordinary_kriging_manual(x_obs, z_obs, x_pred, model)
% x_obs: [n x 2] observed coordinates (lon, lat)
% z_obs: [n x 1] observed values (e.g., vote margins)
% x_pred: [m x 2] prediction coordinates
% model: structure from variogramfit() with fields: type, nugget, sill, range

n_obs = size(x_obs, 1);
n_pred = size(x_pred, 1);
Zhat = zeros(n_pred, 1);

% Select variogram function
params = [model.range, model.sill];  % Gaussian: b = [range, sill]
gamma_fun = @(h) model.nugget + model.func(params, h);



% Compute semivariance matrix between observed points
D_obs = squareform(pdist(x_obs)); % [n x n]
Gamma = gamma_fun(D_obs);
Gamma(end+1, :) = 1; % Lagrange multiplier row
Gamma(:, end+1) = 1;
Gamma(end, end) = 0;

% Loop over prediction locations
for i = 1:n_pred
    d = vecnorm(x_obs - x_pred(i,:), 2, 2);  % [n x 1] distances to prediction point
    gamma0 = gamma_fun(d);
    gamma0(end+1) = 1; % for Lagrange multiplier

    % Solve Kriging system
    weights = Gamma \ gamma0;
    Zhat(i) = sum(weights(1:end-1) .* z_obs);
end
end
