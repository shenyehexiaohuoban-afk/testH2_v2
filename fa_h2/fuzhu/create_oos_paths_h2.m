function OS_paths = create_oos_paths_h2(params, outFile)
%CREATE_OOS_PATHS_H2 Generate OOS Markov paths for hydrogen evaluation.
%
% Unlike the original relief model, the H2 model has no second-layer demand
% sample index. The typhoon Markov path determines beta and terminal states.

if nargin < 2 || isempty(outFile)
    outFile = fullfile(params.dataDir, 'OOS_h2.csv');
end

OS_paths = zeros(params.nbOS, params.T);
for s = 1:params.nbOS
    OS_paths(s, 1) = params.k_init;
    for t = 2:params.T
        OS_paths(s, t) = mc_sample(OS_paths(s, t - 1), params.P_joint);
    end
end

pathNames = arrayfun(@(tt) sprintf('k_t%d', tt), 1:params.T, 'UniformOutput', false);
writetable(array2table(OS_paths, 'VariableNames', pathNames), outFile);
fprintf('Created H2 OOS paths: %s\n', outFile);
end
