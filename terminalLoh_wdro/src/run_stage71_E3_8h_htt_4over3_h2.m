rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(rootDir, 'terminalLoh_wdro', 'src'));
run_stage71_sensitivity_case_h2('E3_8h_htt_4over3');
