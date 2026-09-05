function [OS_paths, layer2_samples] = create_oos_paths(params, outFile, inOutFile)
%CREATE_OOS_PATHS  Generate out-of-sample files for FA/MSP evaluation.
%
% Each row is one sample path; each column is one time stage.
% OS_paths(s,t) is the joint Markov state index for sample path s at stage t.

if nargin < 2 || isempty(outFile)
    outFile = fullfile(params.dataDir, 'OOS.csv');
end
if nargin < 3 || isempty(inOutFile)
    inOutFile = fullfile(params.dataDir, 'inOOS.csv');
end

nbOS = params.nbOS;
T = params.T;

OS_paths = zeros(nbOS, T);
layer2_samples = zeros(nbOS, 1);

for s = 1:nbOS
    OS_paths(s, 1) = params.k_init;
    layer2_samples(s) = randi(params.M);

    for t = 2:T
        OS_paths(s, t) = mc_sample(OS_paths(s, t-1), params.P_joint);
    end
end

pathNames = matlab.lang.makeUniqueStrings(compose("x%d", 1:T));
oosTable = array2table(OS_paths, 'VariableNames', cellstr(pathNames));
sampleTable = table(layer2_samples, 'VariableNames', {'x1'});

writetable(oosTable, outFile);
writetable(sampleTable, inOutFile);
fprintf('Created OOS paths: %s\n', outFile);
fprintf('Created second-layer OOS samples: %s\n', inOutFile);

end
