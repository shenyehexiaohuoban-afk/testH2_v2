function out = stage84_timed_oos_h2(checkpointFile,pathBank,budget,outDir,method,runDir,pid,commit)
%STAGE84_TIMED_OOS_H2 Timed read-only evaluation on a frozen common path bank.

c=load(checkpointFile,'params','modelLib','policy','checkpoint_metadata');
p=c.params; lib=c.modelLib; % Local RHS updates never add cuts.
if string(c.checkpoint_metadata.method)~=method||p.Ni~=4
    error('Stage84:OOSCheckpointIdentity','OOS checkpoint identity mismatch.');
end
if ~exist(outDir,'dir'),mkdir(outDir);end
pathRows=cell(0,numel(path_names()));stageRows=cell(0,numel(stage_names()));
hourTemplate=empty_hour(NaN,method,zeros(1,p.T),p);
hourBatch=hourTemplate([]);batchId=0;pure=0;completed=0;viol=0;
write_oos_status(runDir,method,completed,pure,pid,commit);

for q=1:size(pathBank,1)
    t0=tic; [pr,sr,hr,vcount]=evaluate_one(lib,p,pathBank(q,:),q,method);
    pure=pure+toc(t0); completed=completed+1;viol=viol+vcount;
    pathRows(end+1,:)=pr; %#ok<AGROW>
    stageRows=[stageRows;sr]; %#ok<AGROW>
    hourBatch(end+1)=hr; %#ok<AGROW>
    if numel(hourBatch)>=25
        batchId=batchId+1;save_batch(outDir,batchId,hourBatch,p,method);hourBatch=hourBatch([]);
    end
    writetable(cell2table(pathRows,'VariableNames',path_names()),fullfile(outDir,'oos_path_summary.csv'));
    writetable(cell2table(stageRows,'VariableNames',stage_names()),fullfile(outDir,'oos_stage_site_response.csv'));
    write_oos_status(runDir,method,completed,pure,pid,commit);
    if pure>=budget,break;end
end
if ~isempty(hourBatch),batchId=batchId+1;save_batch(outDir,batchId,hourBatch,p,method);end
meta=table(method,budget,pure,completed,viol,string(checkpointFile),commit,2, ...
    'VariableNames',{'method','requested_pure_time_s','actual_pure_time_s','completed_paths', ...
    'constraint_violations','checkpoint','frozen_commit','stop_flag'});
writetable(meta,fullfile(outDir,'oos_metadata.csv'));
out=struct('completed_paths',completed,'pure_time_s',pure,'constraint_violations',viol);
end

function [pr,srows,hour,vcount]=evaluate_one(lib,p,kpath,pathId,method)
prev=p.x_0;absorbed=false;totalCost=0;terminalValue=0;terminalGap=0;shortage=0;
prod=zeros(4,1);htt=zeros(4);finalInv=prev;minV=inf;minBus=NaN;minHour=NaN;
maxS=0;maxUtil=0;maxFrom=NaN;maxTo=NaN;maxHour=NaN;limited=zeros(4,1);
pvAvail=0;pvUsed=0;gridImport=0;terminalK=0;terminalStage=0;vcount=0;srows={};
hour=empty_hour(pathId,method,kpath,p);

for t=1:p.T
    k=kpath(t);beginInv=prev;status="post_absorb";
    r=zeros(4,1);f=zeros(4);u=zeros(4,1);z=zeros(4,1);ending=prev;
    if ~absorbed
        if p.is_dissipated(k),status="dissipated_absorb";absorbed=true;
        elseif p.is_absorbing(k),status="absorbing_lfNc";absorbed=true;
        elseif p.is_loh_demand_stage(k)
            [tc,ti]=eval_terminal_loh_h2(prev,p,k);terminalValue=tc;terminalGap=sum(ti.shortage);
            totalCost=totalCost+tc;terminalK=k;terminalStage=t;status="loh_demand_stage";absorbed=true;
        else
            if t>6,error('Stage84:OOSNonOperatingStage','Ordinary state reached at non-operating stage %d.',t);end
            m=update_rhs_h2(lib.models{t,k},p,k,t,prev);s=solve_stage_model_h2(m);status="normal";
            eq=m.Aeq*s.xraw-m.beq;ineq=m.A*s.xraw-m.b;v=sqrt(max(s.v_sq,0));trueS=hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
            vcount=vcount+double(max(abs(eq))>1e-6||max([0;ineq])>1e-6|| ...
                min(v,[],'all')<p.hourly_grid.vmin_pu-1e-7||max(v,[],'all')>p.hourly_grid.vmax_pu+1e-7|| ...
                max(trueS,[],'all')>p.hourly_grid.branch_smax_mva+1e-7||any(~isfinite(s.lambda.inventory_eq)));
            totalCost=totalCost+s.obj-s.theta;r=s.rval;f=s.fval;u=s.u_normal;z=s.z_normal;ending=s.xval;
            prod=prod+r;htt=htt+f;shortage=shortage+sum(z);gridImport=gridImport+sum(s.p_grid_kw);
            [vv,ix]=min(v(:));[bb,hh]=ind2sub(size(v),ix);tau=8*(t-1)+hh;
            if vv<minV,minV=vv;minBus=bb;minHour=tau;end
            [ss,ix]=max(trueS(:));[ell,hh]=ind2sub(size(trueS),ix);util=ss/p.hourly_grid.branch_smax_mva;
            if util>maxUtil,maxS=ss;maxUtil=util;maxFrom=p.hourly_grid.branch_from(ell);maxTo=p.hourly_grid.branch_to(ell);maxHour=8*(t-1)+hh;end
            tauVec=8*(t-1)+(1:8);avail=p.hourly_grid.pv_cap_kw(:)*p.hourly_grid.phi48(tauVec(:)).';
            pvAvail=pvAvail+sum(avail,'all');pvUsed=pvUsed+sum(s.p_pv_kw,'all');
            for site=1:4
                bus=p.hourly_grid.site_elec_bus(site);
                for h=1:8
                    below=s.p_el_hourly_kw(site,h)<p.el_cap_kw(site)-1e-6;
                    limited(site)=limited(site)+double(below&&(v(bus,h)<=p.hourly_grid.vmin_pu+1e-5||max(trueS(:,h))/p.hourly_grid.branch_smax_mva>=0.999));
                end
            end
            hour=store_hour(hour,t,k,s,v,trueS,avail,p.k_H2);prev=ending;finalInv=ending;
        end
    end
    for site=1:4
        srows(end+1,:)={method,pathId,t,k,p.S(k,1),p.S(k,2),p.S(k,3),status,site, ...
            beginInv(site),r(site),ending(site),p.D_normal(site,t),u(site),z(site), ...
            sum(f(:,site)),sum(f(site,:)),sum(f(:,site))-sum(f(site,:))}; %#ok<AGROW>
    end
end
if isinf(minV),minV=NaN;end
seq=strjoin(string(kpath),'-');freq=limited/48;
pr={method,pathId,seq,totalCost,terminalValue,terminalGap,shortage,sum(prod),prod(1),prod(2),prod(3),prod(4), ...
    sum(htt,'all'),htt(1,2),htt(1,3),htt(1,4),htt(2,1),htt(2,3),htt(2,4),htt(3,1),htt(3,2),htt(3,4),htt(4,1),htt(4,2),htt(4,3), ...
    finalInv(1),finalInv(2),finalInv(3),finalInv(4),minV,minBus,minHour,maxS,maxUtil,maxFrom,maxTo,maxHour, ...
    limited(1),limited(2),limited(3),limited(4),freq(1),freq(2),freq(3),freq(4),pvAvail,pvUsed,pvAvail-pvUsed, ...
    pvUsed/max(eps,pvAvail),gridImport,terminalK,terminalStage,p.S(kpath(end),1),p.S(kpath(end),2),p.S(kpath(end),3)};
end

function hour=empty_hour(pathId,method,kpath,p)
hour=struct('method',method,'path_id',pathId,'state_sequence',kpath(:).','global_hour',[], ...
    'stage',[],'markov_state',[],'p_el_kw',[],'h2_production_kg',[],'pv_available_kw',[], ...
    'pv_utilized_kw',[],'pv_curtailed_kw',[],'grid_import_kw',[],'bus_voltage_pu',[], ...
    'branch_p_kw',[],'branch_q_kvar',[],'branch_true_s_mva',[], ...
    'site_electrical_bus',p.hourly_grid.site_elec_bus(:).','branch_from',p.hourly_grid.branch_from(:).', ...
    'branch_to',p.hourly_grid.branch_to(:).');
end
function hour=store_hour(hour,t,k,s,v,trueS,avail,kH2)
tau=8*(t-1)+(1:8);hour.global_hour=[hour.global_hour,tau];hour.stage=[hour.stage,repmat(t,1,8)];
hour.markov_state=[hour.markov_state,repmat(k,1,8)];hour.p_el_kw=[hour.p_el_kw,s.p_el_hourly_kw];
hour.h2_production_kg=[hour.h2_production_kg,kH2*s.p_el_hourly_kw];
hour.pv_available_kw=[hour.pv_available_kw,avail];hour.pv_utilized_kw=[hour.pv_utilized_kw,s.p_pv_kw];
hour.pv_curtailed_kw=[hour.pv_curtailed_kw,avail-s.p_pv_kw];hour.grid_import_kw=[hour.grid_import_kw,s.p_grid_kw(:).'];
hour.bus_voltage_pu=[hour.bus_voltage_pu,v];hour.branch_p_kw=[hour.branch_p_kw,s.p_branch_kw];
hour.branch_q_kvar=[hour.branch_q_kvar,s.q_branch_kvar];hour.branch_true_s_mva=[hour.branch_true_s_mva,trueS];
end
function save_batch(outDir,id,hourly_response,p,method)
metadata=struct('method',method,'site_order','Site1,Site2,Site3,Site4','state_order','I1,I2,I3,I4', ...
    'site_electrical_bus',p.hourly_grid.site_elec_bus,'branch_from',p.hourly_grid.branch_from, ...
    'branch_to',p.hourly_grid.branch_to,'voltage_unit','p.u.','power_unit','kW/kVAr','h2_unit','kg');
final=fullfile(outDir,sprintf('oos_hourly_grid_response_batch_%04d.mat',id));temp=[final '.tmp.mat'];
save(temp,'hourly_response','metadata','-v7.3');movefile(temp,final,'f');
end
function n=path_names()
n={'method','path_id','state_sequence','total_cost','terminal_value','terminal_gap_kg','ordinary_shortage_kg', ...
 'total_production_kg','site1_production_kg','site2_production_kg','site3_production_kg','site4_production_kg','total_htt_kg', ...
 'htt_1_to_2_kg','htt_1_to_3_kg','htt_1_to_4_kg','htt_2_to_1_kg','htt_2_to_3_kg','htt_2_to_4_kg','htt_3_to_1_kg','htt_3_to_2_kg','htt_3_to_4_kg','htt_4_to_1_kg','htt_4_to_2_kg','htt_4_to_3_kg', ...
 'final_inventory_site1_kg','final_inventory_site2_kg','final_inventory_site3_kg','final_inventory_site4_kg','minimum_voltage_pu','min_voltage_bus','min_voltage_hour','max_true_branch_mva','max_branch_utilization','max_branch_from','max_branch_to','max_branch_hour', ...
 'site1_grid_limited_count','site2_grid_limited_count','site3_grid_limited_count','site4_grid_limited_count','site1_grid_limited_frequency','site2_grid_limited_frequency','site3_grid_limited_frequency','site4_grid_limited_frequency', ...
 'pv_available_kwh','pv_utilized_kwh','pv_curtailed_kwh','pv_utilization_ratio','grid_import_kwh','terminal_state_k','terminal_stage','final_a','final_loc','final_lf'};
end
function n=stage_names()
n={'method','path_id','stage','markov_state','a','loc','lf','status','site','beginning_inventory_kg','production_kg', ...
 'ending_inventory_kg','ordinary_demand_kg','ordinary_demand_served_kg','shortage_kg','htt_in_kg','htt_out_kg','net_htt_kg'};
end
function write_oos_status(runDir,method,n,pure,pid,commit)
if method=="saa",phase='SAA_OOS';else,phase='DRO_OOS';end
txt=sprintf(['STATUS=RUNNING\nPHASE=%s\nMETHOD=%s\nITERATION=0\nTRAINING_ELAPSED_S=0\n' ...
 'OOS_COMPLETED_PATHS=%d\nOOS_PURE_TIME_S=%.12g\nLATEST_CHECKPOINT=checkpoint_final.mat\n' ...
 'LAST_CHECKPOINT_TIME=\nLAST_UPDATE_TIME=%s\nMATLAB_PID=%d\nFORMAL_FROZEN_COMMIT=%s\n'], ...
 phase,method,n,pure,char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')),pid,commit);
tmp=fullfile(runDir,'RUNNING_STATUS.tmp');fid=fopen(tmp,'w');fprintf(fid,'%s',txt);fclose(fid);
movefile(tmp,fullfile(runDir,'RUNNING_STATUS.txt'),'f');
end
