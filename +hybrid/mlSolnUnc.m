function [x_est,alpha_est, beta_est, A,x_grid] = mlSolnUnc(x_aoa,x_tdoa,x_fdoa,v_fdoa,zeta,C,C_beta,x_ctr,search_size,epsilon,tdoa_ref_idx,fdoa_ref_idx)
% [x_est, alpha_est, beta_est, A,x_grid] = mlSolnUnc(x_aoa,x_tdoa,...
%       x_fdoa,v_fdoa,zeta,C,x_ctr, search_size,epsilon,tdoa_ref_idx,...
%       fdoa_ref_idx)
%
% Construct the ML Estimate by systematically evaluating the log
% likelihood function at a series of coordinates, and returning the index
% of the maximum.  Optionally returns the full set of evaluated
% coordinates, as well.
%
% INPUTS:
%   x_aoa           AOA sensor positions [m]
%   x_tdoa          TDOA sensor positions [m]
%   x_fdoa          FDOA sensor positions [m]
%   v_fdoa          FDOA sensor velocities [m/s]
%   zeta            Combined measurement vector
%   C               Combined measurement error covariance matrix
%   C_beta      nDim x (nAOA + nTDOA + 2*nFDOA) sensor pos/vel error
%               covariance matrix
%   x_ctr           Center of search grid [m]
%   search_size     Vector of search grid sizes [m]
%   epsilon         Desired resolution of search grid [m]
%   tdoa_ref_idx    Scalar index of reference sensor, or nDim x nPair
%                   matrix of sensor pairings for TDOA
%   fdoa_ref_idx    Scalar index of reference sensor, or nDim x nPair
%                   matrix of sensor pairings for FDOA
%
% OUTPUTS:
%   x_est           Estimated source position [m]
%   alpha_est       Cell array with bias estimates for AOA, TDOA, FDOA
%   beta_est        Cell array with estimated sensor positions (and, for
%                   FDOA, sensor velocities).
%   A               Likelihood computed across the entire set of candidate
%                   source positions
%   x_grid          Candidate source positions
%
% Nicholas O'Donoughue
% 22 Feb 2022

% Parse inputs
if nargin < 11 || ~exist('tdoa_ref_idx','var')
    tdoa_ref_idx = [];
end

if nargin < 12 || ~exist('fdoa_ref_idx','var')
    fdoa_ref_idx = [];
end

% Parse inputs sizes
n_dim = size(x_aoa,1);
n_aoa = size(x_aoa,2);
n_tdoa = size(x_tdoa,2);
n_fdoa = size(x_fdoa,2);

assert(size(C,1) == n_aoa + n_tdoa + n_fdoa || size(C,1) == 2*n_aoa + n_tdoa + n_fdoa,'Unable to determine if AOA measurements are 1D or 2D');
do2DAoA = size(C,1) == 2*n_aoa + n_tdoa + n_fdoa;
if do2DAoA
    m_aoa = 2*n_aoa;
else
    m_aoa = n_aoa;
end

% Initialize measurement error and Jacobian function handles
% theta vector contains x, alpha, and beta.  Let's define the
% indices
x_ind = 1:n_dim;
alpha_ind = n_dim + 1:(m_aoa + n_tdoa + n_fdoa);
beta_ind = alpha_ind(end) + 1:(n_dim*(n_aoa + n_tdoa + 2*n_fdoa));

% Set up function handle
% We must take care to ensure that it can handle an n_th x N matrix of
% inputs; for compatibility with how utils.mlSoln will call it.
ell = @(theta) hybrid.loglikelihoodUnc(x_aoa, x_tdoa, x_fdoa, v_fdoa, ...            % reported positions
                                       zeta, C, C_beta, theta, ...
                                       tdoa_ref_idx, fdoa_ref_idx);
        
%% Define center of search space
n_th = n_dim + m_aoa + n_tdoa + n_fdoa + n_dim * (n_aoa + n_tdoa + 2*n_fdoa);
if isempty(x_ctr) || isscalar(x_ctr)
    % x_ctr is empty, use the origin

    th_ctr = [zeros(n_dim,1);
              zeros(m_aoa + n_tdoa + n_fdoa,1); % alpha
              x_aoa(:); x_tdoa(:); x_fdoa(:); v_fdoa(:)]; % beta
elseif numel(x_ctr) == n_dim
    % x_ctr is just the center of the target position
    
    % build th_ctr manually
    th_ctr = [x_ctr; 
              zeros(m_aoa + n_tdoa + n_fdoa,1); % alpha
              x_aoa(:); x_tdoa(:); x_fdoa(:); v_fdoa(:)]; % beta
elseif numel(x_ctr) == n_th
    % the user already specified x_ctr to include alpha and beta
    th_ctr = x_ctr;
else
    error('Unable to parse center of search grid, unexpected number of dimensions received.');
end

%% Define search size
if isempty(search_size) || isscalar(search_size)
    % search_size is empty, use default of
    % 10 km for target dimensions
    % 1 deg for angle bias
    % 10 m for range bias
    % 10 m/s for range-rate bias
    % 25 m for sensor positions
    % 10 m/s for sensor velocities

    search_size = [10e3 * ones(1, n_dim), ...      % x [m]
                   pi/180 * ones(1, m_aoa), ...    % alpha_aoa [rad]
                   10 * ones(1, n_tdoa), ...       % alpha_tdoa [m]
                   10 * ones(1, n_fdoa), ...       % alpha_fdoa [m/s]
                   25 * ones(1, n_aoa*n_dim), ...  % x_aoa [m]
                   25 * ones(1, n_tdoa*n_dim), ... % x_tdoa [m]
                   25 * ones(1, n_fdoa*n_dim), ... % x_fdoa [m]
                   10 * ones(1, n_fdoa*n_dim)];    % v_fdoa [m/s]           
elseif numel(search_size) == n_dim
    % search_size is just defined for the target position
    
    % build th_ctr manually
    search_size = [search_size(:)', ...            % x [m]
                   pi/180 * ones(1, m_aoa), ...    % alpha_aoa [rad]
                   10 * ones(1, n_tdoa), ...       % alpha_tdoa [m]
                   10 * ones(1, n_fdoa), ...       % alpha_fdoa [m/s]
                   25 * ones(1, n_aoa*n_dim), ...  % x_aoa [m]
                   25 * ones(1, n_tdoa*n_dim), ... % x_tdoa [m]
                   25 * ones(1, n_fdoa*n_dim), ... % x_fdoa [m]
                   10 * ones(1, n_fdoa*n_dim)];    % v_fdoa [m/s]      
elseif numel(search_size) == n_th
    % the user already specified search_size to include alpha and beta,
    % do nothing.
else
    error('Unable to parse center of search grid, unexpected number of dimensions received.');
end

%% Define grid resolution
if isempty(epsilon) || isscalar(epsilon)
    % epsilon is empty, compute it based on a default desire of 101 sample
    % points per dimension for target position, and 11 for bias and sensor
    % position/velocity.
    n_elements = [101 * ones(1, n_dim), ...
                  11 * ones(1, m_aoa + n_tdoa + n_fdoa), ...
                  11 * ones(1, n_dim * (n_aoa + n_tdoa + 2*n_fdoa))];

    epsilon = 2*search_size ./ (n_elements-1);

elseif numel(epsilon) == n_dim
    % epsilon is manually defined for target position

    % computer number of elements for each dimension.
    % default is 11 per dimension for bias and sensor position/velocity.
    n_elements = [1 + 2*search_size(x_ind)./epsilon, ...
                  11 * ones(1, m_aoa + n_tdoa + n_fdoa), ...
                  11 * ones(1, n_dim * (n_aoa + n_tdoa + 2*n_fdoa))];
   
    % re-compute grid spacing
    epsilon = 2*search_size ./ (n_elements-1);

elseif numel(epsilon) == n_th
    % the user already specified epsilon to include alpha and beta,
    % do nothing.
else
    error('Unable to parse center of search grid, unexpected number of dimensions received.');
end

%% Call the util function
[th_est,A,x_grid] = utils.mlSoln(ell,th_ctr,search_size,epsilon);

x_est = th_est(x_ind);
alpha_est = th_est(alpha_ind);
beta_est = th_est(beta_ind);
