function [pass,qa] = validate_checkpoint_pathbank_compatibility(params,modelLib,bankFile)
%VALIDATE_CHECKPOINT_PATHBANK_COMPATIBILITY Candidate-agnostic pre-solve gate.
% The bank's first state is the requested initial-state identity.
qa=struct('checkpoint_k_init',NaN,'bank_first_state',NaN,'bank_unique_first_states',[], ...
    'model_exists',false,'model_is_struct',false,'model_has_beq',false, ...
    'model_has_rowMap',false,'model_has_inventory_eq',false,'inventory_eq_valid',false);
pass=false;
if ~isstruct(params)||~isfield(params,'k_init'),return;end
qa.checkpoint_k_init=params.k_init;
if ~isscalar(qa.checkpoint_k_init)||~isfinite(qa.checkpoint_k_init)||qa.checkpoint_k_init~=floor(qa.checkpoint_k_init),return;end
if ~(ischar(bankFile)||isstring(bankFile))||~isfile(bankFile),return;end
paths=readmatrix(bankFile);
if ~isnumeric(paths)||ndims(paths)~=2||isempty(paths),return;end
paths=paths(all(isfinite(paths),2),:);
if isempty(paths),return;end
% Accept either a pure T-column path matrix or a path_id-prefixed CSV.
if isfield(params,'T')&&isscalar(params.T)&&isfinite(params.T)&&size(paths,2)>=params.T+1&&isequal(paths(:,1),(1:size(paths,1)).')
    paths=paths(:,2:params.T+1);
elseif isfield(params,'T')&&isscalar(params.T)&&isfinite(params.T)&&size(paths,2)>=params.T
    paths=paths(:,1:params.T);
end
qa.bank_first_state=paths(1,1);qa.bank_unique_first_states=unique(paths(:,1)).';
if numel(qa.bank_unique_first_states)~=1||qa.bank_first_state~=qa.checkpoint_k_init,return;end
requested=qa.bank_first_state;
if ~isstruct(modelLib)||~isfield(modelLib,'models')||ndims(modelLib.models)<2||requested<1||requested>size(modelLib.models,2),return;end
qa.model_exists=~isempty(modelLib.models{1,requested});
if ~qa.model_exists,return;end
qa.model_is_struct=isstruct(modelLib.models{1,requested});
if ~qa.model_is_struct,return;end
m=modelLib.models{1,requested};qa.model_has_beq=isfield(m,'beq');qa.model_has_rowMap=isfield(m,'rowMap');
if ~qa.model_has_beq||~qa.model_has_rowMap||~isstruct(m.rowMap)||~isfield(m.rowMap,'inventory_eq'),return;end
qa.model_has_inventory_eq=~isempty(m.rowMap.inventory_eq);
idx=m.rowMap.inventory_eq;qa.inventory_eq_valid=qa.model_has_inventory_eq&&isnumeric(idx)&&all(isfinite(idx(:)))&&all(idx(:)==floor(idx(:)))&&all(idx(:)>=1)&&all(idx(:)<=numel(m.beq));
pass=qa.inventory_eq_valid;
end
