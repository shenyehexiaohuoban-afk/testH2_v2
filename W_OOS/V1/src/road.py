"""Read-only frozen road adapter and formal equivalent-distance routing."""
from dataclasses import dataclass
from pathlib import Path
import numpy as np
import pandas as pd
import h5py
from scipy.io import loadmat
from scipy.sparse.csgraph import dijkstra


@dataclass
class Road:
    edges: np.ndarray
    lengths_km: np.ndarray
    consequence: np.ndarray
    closed: np.ndarray
    node_count: int = 33
    identity: str = 'FROZEN_W'

    def __post_init__(self):
        self.edges=np.array(self.edges,dtype=int,copy=True)
        self.lengths_km=np.array(self.lengths_km,dtype=float,copy=True)
        self.consequence=np.array(self.consequence,dtype=float,copy=True)
        self.closed=np.array(self.closed,dtype=bool,copy=True)
        e=len(self.lengths_km)
        if self.edges.shape!=(e,2) or self.consequence.shape!=(6,e) or self.closed.shape!=(6,e):
            raise ValueError('Road shapes must be (edges,2), (edges,), (6,edges)')
        if not np.isfinite(self.lengths_km).all() or np.any(self.lengths_km<=0):
            raise ValueError('Physical lengths must be finite and positive')
        if np.any(self.edges<1) or np.any(self.edges>self.node_count) or np.any(self.edges[:,0]==self.edges[:,1]):
            raise ValueError('Invalid 1-based road endpoint')
        if not np.isfinite(self.consequence).all() or np.any(self.consequence<0) or np.any(self.consequence>1):
            raise ValueError('Cumulative consequence must lie in [0,1]')
        if np.any(np.diff(self.consequence,axis=0)<0) or np.any(self.closed[:-1]&~self.closed[1:]):
            raise ValueError('Road states must preserve cumulative exposure and closure')
        if self.closed[0].any() or self.consequence[0].any():
            raise ValueError('W0 must be intact')

    def weights(self,state):
        return np.where(self.closed[state],np.inf,self.lengths_km*(1+self.consequence[state]))

    def adjacency(self,state):
        a=np.full((self.node_count,self.node_count),np.inf)
        edge_ids=np.full(a.shape,-1,dtype=int)
        np.fill_diagonal(a,0)
        for e,((u,v),w) in enumerate(zip(self.edges,self.weights(state))):
            u-=1;v-=1
            if w<a[u,v]:
                a[u,v]=a[v,u]=w
                edge_ids[u,v]=edge_ids[v,u]=e
        return a,edge_ids

    def matrix(self,state):
        return dijkstra(self.adjacency(state)[0],directed=False)

    def route(self,state,start,target):
        if not (1<=start<=self.node_count and 1<=target<=self.node_count):
            raise ValueError('Route node out of range')
        if start==target:return []
        a,ids=self.adjacency(state)
        dist,pred=dijkstra(a,directed=False,indices=start-1,return_predecessors=True)
        if not np.isfinite(dist[target-1]):return None
        nodes=[target-1]
        while nodes[-1]!=start-1:
            parent=int(pred[nodes[-1]])
            if parent<0 or len(nodes)>self.node_count:raise RuntimeError('Invalid predecessor chain')
            nodes.append(parent)
        nodes.reverse()
        return [(int(ids[u,v]),u+1,v+1) for u,v in zip(nodes[:-1],nodes[1:])]


def geometry(root):
    root=Path(root)
    near=loadmat(root/'data/yuanqi/near_stage_msp_input.mat',squeeze_me=True,struct_as_record=False)['NearStageInput']
    xy=np.asarray(near.Spatial.node_positions,float)
    x=-40+(xy[:,0]-xy[:,0].min())*30/np.ptp(xy[:,0])
    y=10+(xy[:,1]-xy[:,1].min())*25/np.ptp(xy[:,1])
    edges=pd.read_csv(root/'data/yuanqi/stage1_road_edges.csv').sort_values('road_edge_id')[['from_node','to_node']].to_numpy(int)
    uv=edges-1
    lengths=np.hypot(x[uv[:,0]]-x[uv[:,1]],y[uv[:,0]]-y[uv[:,1]])
    return edges,lengths


def load_frozen(root,state_id,path_id):
    root=Path(root)
    if not 1<=state_id<=35 or not 1<=path_id<=15000:raise ValueError('Frozen state/path out of range')
    file=root/('terminalLoh_wdro/partial_temporal_refinement/consequences/state-%03d_five_point_consequence.h5'%state_id)
    with h5py.File(file,'r') as f:
        if int(f['path_id'][path_id-1])!=path_id:raise ValueError('Frozen path identity mismatch')
        p=f['road_cumulative_pClose'][path_id-1]
        closed=f['road_closed_edge'][path_id-1]
        reference=f['C'][path_id-1]
    edges,lengths=geometry(root)
    road=Road(edges,lengths,np.vstack([np.zeros(len(edges)),p]),np.vstack([np.zeros(len(edges),bool),closed]),identity='FROZEN_W_STATE_%03d_PATH_%05d'%(state_id,path_id))
    return road,reference,file
