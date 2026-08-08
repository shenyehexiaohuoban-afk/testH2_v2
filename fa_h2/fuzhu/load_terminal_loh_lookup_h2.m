function [TerminalLOH, mode, sourceUsed, audit] = ...
        load_terminal_loh_lookup_h2(S, NearStageInput, opts)
%LOAD_TERMINAL_LOH_LOOKUP_H2 Map a frozen 35-by-4 C6 table to 4-by-336.

requestedMode = lower(string(required_opt(opts, 'terminal_loh_mode')));
sourceFile = string(required_opt(opts, 'terminal_loh_lookup_file'));
if ~ismember(requestedMode, ["saa", "chi2_eta003"])
    error('load_terminal_loh_lookup_h2:BadMode', ...
        'Unsupported terminal_loh_mode: %s.', requestedMode);
end
if strlength(sourceFile) == 0 || ~isfile(sourceFile)
    error('load_terminal_loh_lookup_h2:MissingFile', ...
        'Missing frozen TerminalLOH lookup file: %s.', sourceFile);
end

tbl = readtable(sourceFile, 'TextType', 'string');
requiredColumns = ["state_id", "intensity", "loc", "lfw", "eta", ...
    "T1_kg", "T2_kg", "T3_kg", "T4_kg", "TerminalLOH_total_kg"];
missingColumns = setdiff(requiredColumns, string(tbl.Properties.VariableNames));
if ~isempty(missingColumns)
    error('load_terminal_loh_lookup_h2:MissingColumns', ...
        'Lookup table is missing columns: %s.', strjoin(missingColumns, ', '));
end
if height(tbl) ~= 35
    error('load_terminal_loh_lookup_h2:BadRowCount', ...
        'Expected 35 lookup rows, got %d.', height(tbl));
end

stateId = double(tbl.state_id);
a = double(tbl.intensity);
loc = double(tbl.loc);
sourceLfw = double(tbl.lfw);
eta = double(tbl.eta);
Trows = [double(tbl.T1_kg), double(tbl.T2_kg), ...
    double(tbl.T3_kg), double(tbl.T4_kg)];
reportedTotal = double(tbl.TerminalLOH_total_kg);

if ~isequal(stateId(:), (1:35).')
    error('load_terminal_loh_lookup_h2:BadStateIds', ...
        'state_id must be exactly 1:35 in frozen order.');
end
expectedStateId = (a - 2) * 7 + loc;
if any(a < 2 | a > 6 | loc < 1 | loc > 7) || ...
        any(expectedStateId ~= stateId)
    error('load_terminal_loh_lookup_h2:BadStateMapping', ...
        'Rows must satisfy state_id=(intensity-2)*7+loc.');
end
if any(sourceLfw ~= 0)
    error('load_terminal_loh_lookup_h2:BadSourceLfw', ...
        'C6 lookup rows must retain the frozen initial-state lfw=0 label.');
end
if any(~isfinite(Trows), 'all') || any(Trows < -1e-10, 'all')
    error('load_terminal_loh_lookup_h2:BadTerminalLOH', ...
        'TerminalLOH values must be finite and nonnegative.');
end
Trows(abs(Trows) < 1e-12) = 0;

totalResidual = sum(Trows, 2) - reportedTotal;
if max(abs(totalResidual)) > 1e-8
    error('load_terminal_loh_lookup_h2:TotalMismatch', ...
        'Maximum row-total mismatch is %.12g kg.', max(abs(totalResidual)));
end

if requestedMode == "saa"
    expectedEta = 0;
    expectedState13 = [133.37697406104255, 36.276354908218, ...
        9.819163734555271, 61.09701879278845];
    expectedState19 = [222.8404658647684, 119.19373755557378, ...
        36.003600360036, 133.3769740610424];
    mode = "saa";
else
    expectedEta = 0.03;
    expectedState13 = [183.83696804374003, 85.37164945673986, ...
        16.365279979335924, 69.55255486498555];
    expectedState19 = [231.2976216031054, 121.91868807193504, ...
        50.09528511681813, 139.65004154041907];
    mode = "chi2_eta003";
end
if max(abs(eta - expectedEta)) > 1e-12
    error('load_terminal_loh_lookup_h2:EtaMismatch', ...
        'Mode %s requires eta %.12g in every row.', requestedMode, expectedEta);
end
if max(abs(Trows(19, :) - expectedState19)) > 1e-9
    error('load_terminal_loh_lookup_h2:State19Mismatch', ...
        'Frozen state19 values do not match mode %s.', requestedMode);
end
if max(abs(Trows(13, :) - expectedState13)) > 1e-9
    error('load_terminal_loh_lookup_h2:State13Mismatch', ...
        'Frozen state13 values do not match mode %s.', requestedMode);
end
if max(abs(Trows(7, :))) > 1e-12
    error('load_terminal_loh_lookup_h2:State7Mismatch', ...
        'Frozen state7 negative control must be exactly zero.');
end

Ni = double(NearStageInput.Sets.num_sites);
if Ni ~= 4 || size(S, 2) ~= 3
    error('load_terminal_loh_lookup_h2:BadDimensions', ...
        'Expected four sites and three-component joint states.');
end
capacity = double(NearStageInput.HydrogenDevice.tank_cap_kg(:)).';
if any(Trows - capacity > 1e-7, 'all')
    error('load_terminal_loh_lookup_h2:CapacityExceeded', ...
        'Lookup TerminalLOH exceeds an active tank capacity.');
end

K = size(S, 1);
TerminalLOH = zeros(Ni, K);
mainStateK = zeros(35, 1);
for rr = 1:35
    matches = find(S(:, 1) == a(rr) & S(:, 2) == loc(rr) & S(:, 3) == 7);
    if numel(matches) ~= 1
        error('load_terminal_loh_lookup_h2:MainStateMissing', ...
            'Expected one main state for a=%d, loc=%d, lf=7.', a(rr), loc(rr));
    end
    expectedK = ((a(rr) - 1) * 7 + (loc(rr) - 1)) * 8 + 7;
    if matches ~= expectedK
        error('load_terminal_loh_lookup_h2:MainStateFormulaMismatch', ...
            'State %d mapped to k=%d instead of formula k=%d.', ...
            stateId(rr), matches, expectedK);
    end
    mainStateK(rr) = matches;
    TerminalLOH(:, matches) = Trows(rr, :).';
end

targetMask = S(:, 1) >= 2 & S(:, 1) <= 6 & ...
    S(:, 2) >= 1 & S(:, 2) <= 7 & S(:, 3) == 7;
if nnz(targetMask) ~= 35 || any(any(TerminalLOH(:, ~targetMask) ~= 0))
    error('load_terminal_loh_lookup_h2:NonTargetPollution', ...
        'Non-target joint states must remain exactly zero.');
end

sourceUsed = sourceFile;
audit = struct();
audit.mode = mode;
audit.source_file = sourceFile;
audit.source_eta = expectedEta;
audit.row_count = height(tbl);
audit.station_order = "T1_kg,T2_kg,T3_kg,T4_kg";
audit.main_state_k = mainStateK;
audit.max_total_residual_kg = max(abs(totalResidual));
audit.nonzero_target_columns = nnz(sum(TerminalLOH, 1) > 0);
audit.target_state_columns = nnz(targetMask);
audit.non_target_max_abs_kg = max(abs(TerminalLOH(:, ~targetMask)), [], 'all');
audit.state7 = Trows(7, :);
audit.state13 = Trows(13, :);
audit.state19 = Trows(19, :);
end

function value = required_opt(opts, fieldName)
if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
    error('load_terminal_loh_lookup_h2:MissingOption', ...
        'Missing required option opts.%s.', fieldName);
end
value = opts.(fieldName);
end
