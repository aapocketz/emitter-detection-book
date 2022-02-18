function [x,x_full] = gdSolnUnc(x_aoa, x_tdoa, x_fdoa, v_fdoa, z,C,x_init,a,b,epsilon,max_num_iterations,force_full_calc,plot_progress,tdoa_ref_idx,fdoa_ref_idx)
% [x,x_full] = gdSolnUnc(x_aoa, x_tdoa, x_fdoa, v_fdoa, z,C,x_init,a,
%                        b,epsilon,max_num_iterations,force_full_calc,
%                        plot_progress,tdoa_ref_idx,fdoa_ref_idx)
%
% Computes the gradient descent solution for hybrid AOA, TDOA, and
% FDOA processing.
%
% Inputs:   
%   x_aoa               AOA sensor positions
%   x_tdoa              TDOA sensor positions
%   x_fdoa              FDOA sensor positions
%   v_fdoa              FDOA sensor velocities
%   z                   Measurement vector
%   C                   Combined error covariance matrix
%   x_init              Initial estimate of source position [m]
%   a                   Backtracking line search parameter
%   b                   Backtracking line search parameter
%   epsilon             Desired position error tolerance (stopping 
%                       condition)
%   max_num_iterations  Maximum number of iterations to perform
%   force_full_calc     Boolean flag to force all iterations (up to
%                       max_num_iterations) to be computed, regardless
%                       of convergence (DEFAULT = False)
%   plot_progress       Boolean flag dictacting whether to plot
%                       intermediate solutions as they are derived 
%                       (DEFAULT = False).
%   tdoa_ref_idx    Scalar index of reference sensor, or nDim x nPair
%                   matrix of sensor pairings for TDOA
%   fdoa_ref_idx    Scalar index of reference sensor, or nDim x nPair
%                   matrix of sensor pairings for FDOA
%
% Outputs:
%   x               Estimated source position
%   x_full          Iteration-by-iteration estimated source positions
%
% Nicholas O'Donoughue
% 17 Feb 2022

% Parse inputs
if nargin < 14 || ~exist('tdoa_ref_idx','var')
    tdoa_ref_idx = [];
end

if nargin < 15 || ~exist('fdoa_ref_idx','var')
    fdoa_ref_idx = [];
end

% Parse inputs sizes
n_dim = size(x_aoa,1);
n_aoa = size(x_aoa,2);
n_tdoa = size(x_tdoa,2);
n_fdoa = size(x_fdoa,2);


assert(size(C,1) == n_aoa + n_tdoa + n_fdoa || size(C,1) == 2*n_aoa + n_tdoa + n_fdoa,'Unable to determine if AOA measurements are 1D or 2D');
do2DAoA = size(C,1) == 2*n_aoa;
if do2DAoA
    m_aoa = 2*n_aoa;
else
    m_aoa = n_aoa;
end

[tdoa_test_idx_vec, tdoa_ref_idx_vec] = utils.parseReferenceSensor(tdoa_ref_idx,n_tdoa);
[fdoa_test_idx_vec, fdoa_ref_idx_vec] = utils.parseReferenceSensor(fdoa_ref_idx,n_fdoa);

m_tdoa = numel(tdoa_test_idx_vec);
m_fdoa = numel(fdoa_test_idx_vec);

% Initialize measurement error and Jacobian function handles
% theta vector contains x, alpha, and beta.  Let's define the
% indices
x_ind = 1:n_dim;
alpha_a_ind = x_ind(end) + (1:m_aoa);
alpha_t_ind = alpha_a_ind(end) + (1:n_tdoa);
alpha_f_ind = alpha_t_ind(end) + (1:n_fdoa);
beta_a_ind = alpha_f_ind(end) + (1:n_dim*n_aoa);
beta_t_ind = beta_a_ind(end) + (1:n_dim*n_tdoa);
beta_fx_ind = beta_t_ind(end) + (1:n_dim*n_fdoa);
beta_fv_ind = beta_fx_ind(end)+ (1:n_dim*n_fdoa);

y = @(theta) z - hybrid.measurement(reshape(theta(beta_a_ind),n_dim,n_aoa), ...   % x_aoa
                                    reshape(theta(beta_t_ind),n_dim,n_tdoa), ...  % x_tdoa
                                    reshape(theta(beta_fx_ind),n_dim,n_fdoa), ... % x_fdoa
                                    reshape(theta(beta_fv_ind),n_dim,n_fdoa), ... % v_fdoa
                                    reshape(theta(x_ind),n_dim,1), ...            % x
                                    tdoa_ref_idx, fdoa_ref_idx, do2DAoA, ...
                                    reshape(theta(alpha_a_ind),m_aoa,1), ...      % alpha_aoa
                                    reshape(theta(alpha_t_ind),n_tdoa,1), ...% alpha_tdoa
                                    reshape(theta(alpha_f_ind),n_fdoa,1));   % alpha_fdoa
J = @(theta) hybrid.jacobianUnc(reshape(theta(beta_a_ind),n_dim,n_aoa), ...   % x_aoa
                                reshape(theta(beta_t_ind),n_dim,n_tdoa), ...  % x_tdoa
                                reshape(theta(beta_fx_ind),n_dim,n_fdoa), ... % x_fdoa
                                reshape(theta(beta_fv_ind),n_dim,n_fdoa), ... % v_fdoa
                                reshape(theta(x_ind),n_dim,1), ...            % x
                                tdoa_ref_idx, fdoa_ref_idx, do2DAoA, ...
                                reshape(theta(alpha_a_ind),m_aoa,1), ...      % alpha_aoa
                                reshape(theta(alpha_t_ind),n_tdoa,1), ...% alpha_tdoa
                                reshape(theta(alpha_f_ind),n_fdoa,1));   % alpha_fdoa

% Parse the TDOA and FDOA reference indices together
test_idx_vec = cat(2,tdoa_test_idx_vec, n_tdoa + fdoa_test_idx_vec);
ref_idx_vec = cat(2,tdoa_ref_idx_vec, n_tdoa + fdoa_ref_idx_vec);

% For now, we assume the AOA is independent of TDOA/FDOA
C_aoa = C(1:m_aoa, 1:m_aoa);
C_tfdoa = C(m_aoa+1:end, m_aoa+1:end);
C_tilde = blkdiag(C_aoa, utils.resampleCovMtx(C_tfdoa, test_idx_vec, ref_idx_vec));

% Build the initial theta vector
th_init = [x_init; zeros(m_aoa+n_tdoa+n_fdoa,1); x_aoa(:); x_tdoa(:); x_fdoa(:); v_fdoa(:)];

% Call the generic Least Square solver
[th,th_full] = utils.gdSoln(y,J,C_tilde,th_init,a,b,epsilon,max_num_iterations,force_full_calc,plot_progress);

% Grab the x coordinates
x = th(x_ind);
x_full = th_full(x_ind,:);

