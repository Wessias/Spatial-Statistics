%Load image and fix
x = imread("titan.jpg");
%x = imread("rosetta.jpg");

x = im2gray(x);
x = im2double(x);
%%
[m,n] = size(x);

%Flatten
x_vec = x(:);

% Percentage of points observed
p_c = 0.42;

N = round(p_c * m * n);

%Random observations
ind = randperm(m*n);
ind_obs = ind(1:N);
ind_mis = ind(N+1:end);

x_obs = x_vec(ind_obs);
x_mis = x_vec(ind_mis);

[X,Y] = meshgrid(1:n,1:m);

loc_all = [X(:), Y(:)];
loc_obs = loc_all(ind_obs, :);

sample = min(10000,N);

loc_sub = loc_obs(1:sample, :);
x_sub = x_obs(1:sample);

D = squareform(pdist(loc_sub));

%%

vario_emp = emp_variogram(D, x_sub, 40);
%%

fixed = struct("nu", 1);
pars = cov_ls_est(x_sub, "matern", vario_emp, fixed);
disp(pars);

vario_fit = matern_variogram(vario_emp.h, pars.sigma, pars.kappa, pars.nu, pars.sigma_e);

figure;
plot(vario_emp.h, vario_emp.variogram, "bo-", "DisplayName", "Empirical");
hold on;
plot(vario_emp.h, vario_fit, "r-", "DisplayName","Fitted");
xlabel("Distance"); ylabel("Semivariance");
legend;

%%
tau = 2 * pi / (pars.sigma^2);
kappa = pars.kappa;
%kappa = 0.09;

q1 = kappa^4 * [0 0 0 0 0; 0 0 0 0 0; 0 0 1 0 0; 0 0 0 0 0; 0 0 0 0 0];
q2 = 2*kappa^2 * [0 0 0 0 0; 0 0 -1 0 0; 0 -1 4 -1 0; 0 0 -1 0 0; 0 0 0 0 0];
q3 = [0 0 1 0 0; 0 2 -8 2 0; 1 -8 20 -8 1;0 2 -8 2 0; 0 0 1 0 0];
q = q1 + q2 +q3;
Q = tau * stencil2prec([m,n],q);

Qop = Q(ind_obs, ind_mis);
Qo = Q(ind_obs,ind_obs);
Qp = Q(ind_mis,ind_mis);

mu_mis = -Qp \ (Qop' * x_obs);


x_recon = zeros(m*n,1);
x_recon(ind_obs) = x_obs;
x_recon(ind_mis) = mu_mis;

x_recon = reshape(x_recon, m, n);

%% PLOT ORIGINAL AND RECONSTRUCTED
figure;
subplot(1,2,1);
imshow(x);
title('True Image');

subplot(1,2,2);
imshow(x_recon); 
%scatter(loc_obs(:,1), loc_obs(:,2), 1 );
title('Reconstructed Image (GMRF)');

%% PLOT ORIGNAL, RECONSTRUCTED AND ERROR

figure;
subplot(1,3,1);
imshow(x);
title('True Image');

subplot(1,3,2);
imshow(x_recon); 
%scatter(loc_obs(:,1), loc_obs(:,2), 1 );
title('Reconstructed Image (GMRF)');

subplot(1,3,3);
imshow(abs(x-x_recon)); colorbar; axis image;
title("Error");

%% Only reconstructed + dots on observed points
figure;
imshow(x_recon); hold on;
scatter(loc_obs(:,1), loc_obs(:,2), 1 );
title('Reconstructed Image (GMRF)'); axis image;