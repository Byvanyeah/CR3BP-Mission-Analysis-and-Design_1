%% CR3BP Library %% 
% Sergio Cuevas del Valle
% Date: 31/12/20
% File: null_flight_path.m 
% Issue: 0 
% Validated: 

%% Null flight path angle %%
% This function contains a handle function to define orbital events to stop integration.

function [Pos, isterminal, dir] = null_flight_path(~, x, R)
    %Constants 
    x = x(1:6)-[R; zeros(3,1)];                               %Relative state vector to the primary of interest
    v = cross(x(1:3), x(4:6));                           %Velocity vector 
    
    %Event definition
    Pos = acos(norm(v)/(norm(x(1:3))*norm(x(4:6))));     %Flight path angle        
    isterminal = 1; 
    dir = 0;                                             %Direction of the crossing
end