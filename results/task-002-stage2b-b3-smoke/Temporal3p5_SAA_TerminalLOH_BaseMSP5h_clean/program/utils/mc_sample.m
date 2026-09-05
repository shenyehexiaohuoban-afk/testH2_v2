function k_next = mc_sample(current_state, P_joint)
%MC_SAMPLE  Sample next Markov state from the joint transition matrix.
%
% Input:
%   current_state : current joint state index k
%   P_joint       : K-by-K joint transition probability matrix
%
% Output:
%   k_next        : sampled next joint state index

prob = P_joint(current_state, :);

% Normalize to guard against tiny floating-point row-sum errors.
rowSum = sum(prob);
if rowSum <= 0
    error('mc_sample:InvalidProb', ...
        'Transition probability row %d has non-positive sum.', current_state);
end
prob = prob / rowSum;

cdf = cumsum(prob);
u = rand();

k_next = find(u <= cdf, 1, 'first');

% Fallback for rare floating-point edge cases.
if isempty(k_next)
    k_next = numel(prob);
end

end
