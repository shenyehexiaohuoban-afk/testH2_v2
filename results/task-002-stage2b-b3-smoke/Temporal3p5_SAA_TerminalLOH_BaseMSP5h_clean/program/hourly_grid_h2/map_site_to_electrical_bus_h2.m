function siteElecBus = map_site_to_electrical_bus_h2()
%MAP_SITE_TO_ELECTRICAL_BUS_H2 Stage-79 synthetic benchmark coupling.
%
% This must not be inferred from, or aliased to, the road-node mapping.
% Stage-77 found only an inactive schematic candidate, not a physical GIS
% mapping.  Stage-79 explicitly freezes the candidate as a new assumption.

siteElecBus = [24; 14; 18; 31];
end
