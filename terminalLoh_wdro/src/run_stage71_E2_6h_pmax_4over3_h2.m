rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'src'));
run_stage71_sensitivity_case_h2('E2_6h_pmax_4over3');
