function opts = h2_stage90a_candidate_options(rootDir, K_terminal_kg)
%H2_STAGE90A_CANDIDATE_OPTIONS Explicit Stage-90A candidate configuration.
%
% The current MSP has no terminal duration variable, so the candidate freezes
% one aggregate 160 kg action unless an explicit value is passed. This helper
% never changes the default model.

if nargin < 1 || isempty(rootDir); rootDir = pwd; end
if nargin < 2 || isempty(K_terminal_kg)
    K_terminal_kg = 160;
end
if ~isscalar(K_terminal_kg) || ...
        ~isfinite(K_terminal_kg) || K_terminal_kg < 0
    error('h2_stage90a_candidate_options:MissingCapacity', ...
        'Pass an explicit finite nonnegative K_terminal_kg.');
end
opts = h2_default_options(rootDir);
opts.terminal_recourse_mode = 'TERMINAL_REDISTRIBUTION';
opts.K_terminal_kg = double(K_terminal_kg);
opts.terminal_capacity_mapping = 'FROZEN_AGGREGATE_160_KG';
opts.runTraining = false;
opts.runEvaluation = false;
opts.runSelectedPathDiagnostics = false;
end
