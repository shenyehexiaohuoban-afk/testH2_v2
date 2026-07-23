function result = audit_a6_historical_wind_data_h2(cmaDir,cmaArchive,ibtracsFile,config)
%AUDIT_A6_HISTORICAL_WIND_DATA_H2 Parse CMA a=6 records and cross-check IBTrACS.

if ~isfolder(cmaDir), error('CMA best-track directory is missing: %s',cmaDir); end
if ~isfile(cmaArchive), error('CMA archive is missing: %s',cmaArchive); end
if ~isfile(ibtracsFile), error('IBTrACS file is missing: %s',ibtracsFile); end

files = dir(fullfile(cmaDir,'CH*BST.txt'));
[~,order] = sort({files.name}); files = files(order);
expectedNames = compose('CH%dBST.txt',(1949:2024).');
actualNames = string({files.name}).';
yearFilesPass = numel(files)==76 && isequal(actualNames,expectedNames);
if ~yearFilesPass
    error('Expected the complete CMA CH1949BST.txt through CH2024BST.txt set.');
end

rows = cell(10000,10); rr = 0;
cat6BelowThreshold = 0; nonCat6AboveThreshold = 0;
fileHashes = strings(numel(files),1); fileBytes = zeros(numel(files),1);
for ff = 1:numel(files)
    fileName = fullfile(files(ff).folder,files(ff).name);
    fileHashes(ff) = sha256_file(fileName); fileBytes(ff) = files(ff).bytes;
    fid = fopen(fileName,'r');
    if fid < 0, error('Could not open CMA file: %s',fileName); end
    cleanup = onCleanup(@()fclose(fid));
    stormId = ""; stormName = ""; stormKey = "";
    while true
        line = fgetl(fid); if ~ischar(line), break; end
        tokens = string(regexp(strtrim(line),'\s+','split'));
        if isempty(tokens) || strlength(tokens(1))==0, continue; end
        if tokens(1)=="66666"
            if numel(tokens)<8, error('Malformed CMA header in %s.',files(ff).name); end
            stormId = tokens(2); stormName = tokens(8);
            stormKey = erase(string(files(ff).name),"BST.txt")+"|"+stormId+"|"+stormName;
            continue;
        end
        if numel(tokens)<6 || isempty(regexp(tokens(1),'^\d{10}$','once')), continue; end
        category = str2double(tokens(2)); windMps = str2double(tokens(6));
        if ~isfinite(category) || ~isfinite(windMps)
            error('Nonfinite CMA category or wind in %s.',files(ff).name);
        end
        if category==6 && windMps<config.a6ThresholdMps
            cat6BelowThreshold = cat6BelowThreshold+1;
        elseif category~=6 && windMps>=config.a6ThresholdMps
            nonCat6AboveThreshold = nonCat6AboveThreshold+1;
        end
        if category~=6 || windMps<config.a6ThresholdMps, continue; end
        rr = rr+1;
        if rr>size(rows,1), rows(end+5000,10)={[]}; end %#ok<AGROW>
        rows(rr,:) = {string(files(ff).name),stormKey,stormId,stormName, ...
            tokens(1),str2double(extractBefore(tokens(1),5)),category, ...
            str2double(tokens(3))/10,str2double(tokens(4))/10,windMps};
    end
    clear cleanup;
end
rows = rows(1:rr,:);
cmaRecords = cell2table(rows,'VariableNames', ...
    {'source_file','storm_key','international_id','storm_name','valid_time_utc', ...
    'year','cma_category','latitude_deg_n','longitude_deg_e','wind_2min_mps'});
cmaRecords = sortrows(cmaRecords,{'valid_time_utc','storm_key'});
if height(cmaRecords)==0, error('No CMA a=6 records satisfy the accepted threshold.'); end

cmaWind = double(cmaRecords.wind_2min_mps);
[stormKeys,~,stormGroup] = unique(cmaRecords.storm_key,'stable'); %#ok<ASGLU>
stormPeak = splitapply(@max,cmaWind,stormGroup);

ibWindKts = double(ncread(ibtracsFile,'cma_wind'));
ibCategory = double(ncread(ibtracsFile,'cma_cat'));
ibTime = double(ncread(ibtracsFile,'time'));
ibFlags = ncread(ibtracsFile,'iflag');
ibCmaFlag = squeeze(ibFlags(3,:,:));
ibDate = datetime(1858,11,17)+days(ibTime);
ibMpsAll = ibWindKts*config.knotToMps;
ibMask = ibCategory==6 & ibWindKts>0 & year(ibDate)>=1949 & ...
    year(ibDate)<=2024 & ibCmaFlag=='O' & ibMpsAll>=config.a6ThresholdMps;
ibMps = double(ibMpsAll(ibMask));
ibRoundedMps = round(ibMps);

sortedCma = sort(cmaWind); sortedIbRounded = sort(ibRoundedMps);
crosscheckCountPass = numel(sortedCma)==numel(sortedIbRounded);
if crosscheckCountPass
    sortedMultisetPass = isequal(sortedCma,sortedIbRounded);
    maxRoundedDifference = max(abs(sortedCma-sortedIbRounded));
else
    sortedMultisetPass = false; maxRoundedDifference = Inf;
end

summaryRows = {
    "CMA_record_level",height(cmaRecords),numel(unique(cmaRecords.storm_key)), ...
    min(cmaRecords.year),max(cmaRecords.year),numel(unique(cmaRecords.year)), ...
    min(cmaWind),mean(cmaWind),nearest_rank(cmaWind,50),nearest_rank(cmaWind,75), ...
    nearest_rank(cmaWind,90),nearest_rank(cmaWind,95),nearest_rank(cmaWind,99),max(cmaWind), ...
    "m/s","2-minute","category=6 and wind>=51 m/s; each CMA best-track time record";
    "CMA_storm_peak",numel(stormPeak),numel(stormPeak), ...
    min(cmaRecords.year),max(cmaRecords.year),numel(unique(cmaRecords.year)), ...
    min(stormPeak),mean(stormPeak),nearest_rank(stormPeak,50),nearest_rank(stormPeak,75), ...
    nearest_rank(stormPeak,90),nearest_rank(stormPeak,95),nearest_rank(stormPeak,99),max(stormPeak), ...
    "m/s","2-minute","maximum selected a=6 record per CMA storm; secondary diagnostic";
    "IBTrACS_CMA_original",numel(ibMps),NaN,1949,2024,NaN, ...
    min(ibMps),mean(ibMps),nearest_rank(ibMps,50),nearest_rank(ibMps,75), ...
    nearest_rank(ibMps,90),nearest_rank(ibMps,95),nearest_rank(ibMps,99),max(ibMps), ...
    "m/s converted from knots","CMA source 2-minute","cma_wind with CMA iflag=O only; no interpolated or other-agency winds";
    "IBTrACS_CMA_rounded_mps",numel(ibRoundedMps),NaN,1949,2024,NaN, ...
    min(ibRoundedMps),mean(ibRoundedMps),nearest_rank(ibRoundedMps,50),nearest_rank(ibRoundedMps,75), ...
    nearest_rank(ibRoundedMps,90),nearest_rank(ibRoundedMps,95),nearest_rank(ibRoundedMps,99),max(ibRoundedMps), ...
    "m/s rounded","CMA source 2-minute","cross-check representation matching integer CMA source files"};
summary = cell2table(summaryRows,'VariableNames', ...
    {'sample_scope','sample_count','unique_storm_count','year_min','year_max', ...
    'years_with_records','minimum_mps','mean_mps','median_mps','q75_mps', ...
    'q90_mps','q95_mps','q99_mps','maximum_mps','unit','wind_average_period', ...
    'sample_definition'});

crosscheck = table(height(cmaRecords),numel(ibMps),crosscheckCountPass, ...
    sortedMultisetPass,maxRoundedDifference,cat6BelowThreshold, ...
    nonCat6AboveThreshold,"CMA_WIND",3,"O",config.knotToMps, ...
    'VariableNames',{'cma_selected_record_count','ibtracs_selected_record_count', ...
    'record_count_match','rounded_wind_multiset_match','max_rounded_mps_difference', ...
    'cma_category6_below_51_count','cma_noncategory6_at_or_above_51_count', ...
    'ibtracs_field','ibtracs_cma_agency_index','required_iflag', ...
    'knot_to_mps_factor'});

fileAudit = table(actualNames,fileBytes,fileHashes,'VariableNames', ...
    {'source_file','bytes','sha256'});
combinedText = strjoin(actualNames+"|"+string(fileBytes)+"|"+fileHashes,newline);

result = struct(); result.cma_records = cmaRecords;
result.summary = summary; result.crosscheck = crosscheck;
result.file_audit = fileAudit; result.cma_archive_sha256 = sha256_file(cmaArchive);
result.ibtracs_sha256 = sha256_file(ibtracsFile);
result.cma_combined_file_manifest_sha256 = sha256_text(combinedText);
result.complete_year_files_pass = yearFilesPass;
result.data_comparable_pass = crosscheckCountPass && sortedMultisetPass && ...
    maxRoundedDifference==0;
result.sample_sufficient_pass = height(cmaRecords)>=config.minimumA6SampleCount;
result.sensitivity_values_mps = [config.currentA6Mps, ...
    nearest_rank(cmaWind,50),nearest_rank(cmaWind,90),nearest_rank(cmaWind,95)];
end

function value = nearest_rank(x,p)
x = sort(double(x(:))); x = x(isfinite(x));
if isempty(x), value=NaN; return; end
value = x(max(1,min(numel(x),ceil(p/100*numel(x)))));
end

function hash = sha256_file(fileName)
fid=fopen(fileName,'rb'); if fid<0,error('Could not open %s.',fileName);end
cleanup=onCleanup(@()fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes=fread(fid,1024*1024,'*uint8');if isempty(bytes),break;end
    md.update(typecast(bytes,'int8'));
end
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end

function hash = sha256_text(value)
md=java.security.MessageDigest.getInstance('SHA-256');
bytes=unicode2native(char(value),'UTF-8');md.update(typecast(uint8(bytes),'int8'));
digest=typecast(md.digest(),'uint8');hash=lower(string(reshape(dec2hex(digest,2).',1,[])));
end
