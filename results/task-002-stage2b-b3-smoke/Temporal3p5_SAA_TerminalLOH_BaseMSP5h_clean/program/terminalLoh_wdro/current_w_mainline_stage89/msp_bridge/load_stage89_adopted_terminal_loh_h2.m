function [TerminalLOH, mode, audit] = load_stage89_adopted_terminal_loh_h2( ...
        S, NearStageInput, requestedMode, sourceFile)
%LOAD_STAGE89_ADOPTED_TERMINAL_LOH_H2 Strict Stage89K adopted-table loader.

if nargin < 3 || isempty(requestedMode)
    requestedMode = "saa";
end
requestedMode = lower(string(requestedMode));
if requestedMode == "chi2_eta003"
    requestedMode = "dro";
end
if ~ismember(requestedMode, ["saa", "dro"])
    error('Stage89M:BadMode', 'Stage89 adopted mode must be SAA or DRO.');
end

bridgeDir = fileparts(mfilename('fullpath'));
tableDir = fullfile(fileparts(bridgeDir), 'terminal_tables');
if requestedMode == "saa"
    expectedMode = "SAA";
    expectedEta = 0;
    acceptedSha = "b74433fe8a19caedb75ac3071225480e279c136f3d1285ba503a184f12c5fcdc";
    defaultFile = fullfile(tableDir, 'terminal_loh_temporal3p5_saa_candidate.csv');
else
    expectedMode = "DRO";
    expectedEta = 0.03;
    error('Stage89M:DRODisabled', 'DRO mode is not enabled in the SAA package.');
end
if nargin < 4 || isempty(sourceFile)
    sourceFile = defaultFile;
end
sourceFile = string(sourceFile);
if ~isfile(sourceFile)
    error('Stage89M:MissingTable', 'Missing Stage89K adopted table: %s', sourceFile);
end

sourceSha = sha256_file(sourceFile);
if sourceSha ~= acceptedSha
    error('Stage89M:SourceHashMismatch', ...
        'Stage89K %s table SHA mismatch: expected %s, got %s.', ...
        expectedMode, acceptedSha, sourceSha);
end

tbl = readtable(sourceFile, 'TextType', 'string');
required = ["state_id","intensity","loc","lfw","eta", ...
    "T1_kg","T2_kg","T3_kg","T4_kg","TerminalLOH_total_kg", ...
    "TERMINALLOH_VERSION","MODE","STATE_COUNT","SITE_COUNT", ...
    "ADOPTED_DRO_ETA","TANK_CAP_KG","SOURCE_STAGE","SOURCE_RUN"];
missing = setdiff(required, string(tbl.Properties.VariableNames));
if ~isempty(missing)
    error('Stage89M:MissingColumns', 'Stage89K table missing columns: %s.', strjoin(missing, ', '));
end
if height(tbl) ~= 35
    error('Stage89M:BadRowCount', 'Stage89K table must contain exactly 35 states.');
end

stateId = double(tbl.state_id);
a = double(tbl.intensity);
loc = double(tbl.loc);
lfw = double(tbl.lfw);
eta = double(tbl.eta);
Trows = [double(tbl.T1_kg), double(tbl.T2_kg), double(tbl.T3_kg), double(tbl.T4_kg)];
reportedTotal = double(tbl.TerminalLOH_total_kg);
if ~isequal(stateId(:), (1:35).') || any((a-2)*7+loc ~= stateId) || any(lfw ~= 0)
    error('Stage89M:StateMappingMismatch', ...
        'Stage89K rows must be a2 loc1..7 through a6 loc1..7 in state_id order.');
end
if any(~isfinite(Trows), 'all') || any(Trows < -1e-10, 'all') || ...
        max(abs(sum(Trows,2)-reportedTotal)) > 1e-8
    error('Stage89M:BadTerminalValues', 'Stage89K values are invalid or totals do not match.');
end
if max(abs(eta-expectedEta)) > 1e-12 || ...
        any(tbl.TERMINALLOH_VERSION ~= "TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE") || ...
        any(upper(tbl.MODE) ~= expectedMode) || ...
        any(double(tbl.STATE_COUNT) ~= 35) || any(double(tbl.SITE_COUNT) ~= 4) || ...
        any(abs(double(tbl.ADOPTED_DRO_ETA)-0.0) > 1e-12) || ...
        any(tbl.TANK_CAP_KG ~= "[300,200,100,200]") || ...
        any(tbl.SOURCE_STAGE ~= "Temporal3p5_DurationAware_SAA_Formulation") || ...
        any(tbl.SOURCE_RUN ~= "partial_temporal_refinement/terminalLoh_saa_base2/run-001")
    error('Stage89M:MetadataMismatch', 'Temporal3p5 candidate table metadata/version/mode gate failed.');
end

capacity = double(NearStageInput.HydrogenDevice.tank_cap_kg(:)).';
if ~isequal(capacity, [300,200,100,200])
    error('Stage89M:CapacityMismatch', ...
        'Stage89K adopted loader requires tank capacities [300,200,100,200] kg.');
end
if any(Trows-capacity > 1e-7, 'all')
    error('Stage89M:CapacityExceeded', 'Stage89K table exceeds an active tank capacity.');
end

TerminalLOH = zeros(4, size(S,1));
mainStateK = zeros(35,1);
for rr = 1:35
    matches = find(S(:,1)==a(rr) & S(:,2)==loc(rr) & S(:,3)==7);
    expectedK = ((a(rr)-1)*7+(loc(rr)-1))*8+7;
    if numel(matches) ~= 1 || matches ~= expectedK
        error('Stage89M:JointStateMappingMismatch', 'State %d joint-state mapping failed.', rr);
    end
    mainStateK(rr) = matches;
    TerminalLOH(:,matches) = Trows(rr,:).';
end
targetMask = S(:,1)>=2 & S(:,1)<=6 & S(:,2)>=1 & S(:,2)<=7 & S(:,3)==7;
if nnz(targetMask) ~= 35 || any(TerminalLOH(:,~targetMask) ~= 0, 'all')
    error('Stage89M:NonTargetPollution', 'Non-target TerminalLOH columns must remain zero.');
end

mode = lower(expectedMode);
audit = struct('pass',true,'mode',mode,'source_file',sourceFile, ...
    'source_sha256',sourceSha,'table_version',"TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE", ...
    'source_stage',"Temporal3p5_DurationAware_SAA_Formulation", ...
    'source_run',"partial_temporal_refinement/terminalLoh_saa_base2/run-001",'eta',expectedEta, ...
    'adopted_dro_eta',0.0,'state_count',35,'site_count',4, ...
    'station_order',"Site1,Site2,Site3,Site4", ...
    'main_state_k',mainStateK,'tank_capacity_kg',capacity, ...
    'non_target_max_abs_kg',max(abs(TerminalLOH(:,~targetMask)),[],'all'));
end

function value = sha256_file(path)
md = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
fid = fopen(path, 'rb');
if fid < 0
    error('Stage89M:HashOpen', 'Cannot open file for SHA256: %s.', path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    block = fread(fid, 1024*1024, '*uint8');
    if isempty(block), break; end
    md.update(typecast(block, 'int8'));
end
digest = typecast(md.digest(), 'uint8');
value = string(lower(reshape(dec2hex(digest,2).',1,[])));
end
