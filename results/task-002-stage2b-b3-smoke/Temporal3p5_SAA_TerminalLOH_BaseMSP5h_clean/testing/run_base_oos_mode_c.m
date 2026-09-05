function run_base_oos_mode_c(mode)
%RUN_BASE_OOS_MODE_C OOS framework entry; it creates no data until called.
if nargin < 1 || strlength(string(mode)) == 0, mode = "VALIDATE_RULE"; end
mode=upper(strtrim(string(mode))); testingRoot=fileparts(mfilename('fullpath')); packageRoot=fileparts(testingRoot); projectRoot=fileparts(fileparts(fileparts(fileparts(packageRoot)))); ruleFile=fullfile(projectRoot,'codex_rule','OOS_rule.md');
if ~isfile(ruleFile), error('BaseTemplate:OOSRule','Canonical OOS rule not found: %s',ruleFile); end
if mode == "VALIDATE_RULE", fprintf('Canonical OOS rule: %s\n',ruleFile); return; end
if mode ~= "RUN", error('BaseTemplate:OOSMode','Expected VALIDATE_RULE or RUN.'); end
checkpoint=strtrim(getenv('BASE_OOS_CHECKPOINT')); if isempty(checkpoint), error('BaseTemplate:OOSInput','Set BASE_OOS_CHECKPOINT to a completed Base checkpoint.'); end
if ~isfile(checkpoint), error('BaseTemplate:OOSInput','Checkpoint not found: %s',checkpoint); end
error('BaseTemplate:OOSNotConfigured','Select an experiment-specific OOS sample bank and output directory before running.');
end
