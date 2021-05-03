%% Autonomous RVD and docking in the CR3BP %% 
% Sergio Cuevas del Valle % 
% 01/04/21 % 

%% GNC 8: Two-impulsive rendezvous using the target approach strategy %% 
% This script provides an interface to test the target apprach strategy for the rendezvous problem. 

% The relative motion of two spacecraft in the same halo orbit (closing and RVD phase) around L1 in the
% Earth-Moon system is analyzed.

% In the relative phase space, the relative particle is driven to the
% origin of the synodic frame.

% Units are non-dimensional and solutions are expressed in the Lagrange
% points reference frame as defined by Howell, 1984.

%% Set up %%
%Set up graphics 
set_graphics();

%Integration tolerances (ode113)
options = odeset('RelTol', 2.25e-14, 'AbsTol', 1e-22);  

%% Contants and initial data %% 
%Time span 
dt = 1e-3;                          %Time step
tf = 0.6;                           %Rendezvous time
tspan = 0:dt:tf;                    %Integration time span
tspann = 0:dt:2*pi;                 %Integration time span

%CR3BP constants 
mu = 0.0121505;                     %Earth-Moon reduced gravitational parameter
L = libration_points(mu);           %System libration points
Lem = 384400e3;                     %Mean distance from the Earth to the Moon

%Differential corrector set up
maxIter = 50;                       %Maximum number of iterations
tol = 1e-10;                        %Differential corrector tolerance

%% Initial conditions and halo orbit computation %%
%Halo characteristics 
Az = 200e6;                                                 %Orbit amplitude out of the synodic plane. 
Az = dimensionalizer(Lem, 1, 1, Az, 'Position', 0);         %Normalize distances for the E-M system
Ln = 1;                                                     %Orbits around L1
gamma = L(end,Ln);                                          %Li distance to the second primary
m = 1;                                                      %Number of periods to compute

%Compute a halo seed 
halo_param = [1 Az Ln gamma m];                             %Northern halo parameters
[halo_seed, period] = object_seed(mu, halo_param, 'Halo');  %Generate a halo orbit seed

%Correct the seed and obtain initial conditions for a halo orbit
[target_orbit, ~] = differential_correction('Plane Symmetric', mu, halo_seed, maxIter, tol);

%% Modelling in the synodic frame %% 
index = fix(tf/dt);                                         %Rendezvous point
r_t0 = target_orbit.Trajectory(100,1:6);                    %Initial target conditions
r_c0 = target_orbit.Trajectory(1,1:6);                      %Initial chaser conditions 
rho0 = r_c0-r_t0;                                           %Initial relative conditions
s0 = [r_t0 rho0].';                                         %Initial conditions of the target and the relative state
Phi = eye(length(r_t0));                                    %Initial STM
Phi = reshape(Phi, [length(r_t0)^2 1]);                     %Initial STM
s0 = [s0; Phi];                                             %Initial conditions

%Integration of the model
[t, S] = ode113(@(t,s)nlr_model(mu, true, false, true, 'Encke', t, s), tspann, s0, options);
Sn = S;              

%Reconstructed chaser motion 
S_rc = S(:,1:6)+S(:,7:12);                                  %Reconstructed chaser motion via Encke method

%% GNC: two impulsive rendezvous, generalized targetting approach %%
%Differential corrector set up
maxIter = 100;                              %Maximum number of iterations
tol = 1e-5;                                 %Differential corrector tolerance
S = S(1:index,:);                           %Restrict the time integration span
T = index*dt;                               %Flight time along the arc
GoOn = true;                                %Convergence boolean 
iter = 1;                                   %Initial iteration 

%Preallocation 
dV = zeros(3,maxIter);                      %Targeting impulse

%Cost function matrices
R = eye(3);                                 %Penalty on the impulse
Qt = eye(6);                                %Penalty on the state error
M = 0.1*eye(6);                             %Penalty on the state noise
Omegat = [zeros(3,3); eye(3)];              %Derivative of the state vector with respect to the impulse
Rr = eye(3);                                %Rotational misalignment of the thrusters

%Select measuring times 
noise = true;                               %Boolean to account for state noise
measurements = 3;                           %Number of noise measurements
times = T*rand(1,measurements);             %Times to measure the state noise
times = fix(times/dt);                      %Position along the time span to measure the state noise
times = sort(times);                        %Sort the times at which the noise measurements are taken
ns = 1e-6*ones(6,1);                        %Initial state noise 
sigma = 0.01;                               %Velocity noise dependance on the velocity impulse

%Cost function 
cost = 'Position';                          %Make impulses to target position

%Initial conditions 
S0 = s0;

%Implementation 
while ((GoOn) && (iter < maxIter))
    %Compute the complete STM
    STM = reshape(S(end,13:end), [length(r_t0) length(r_t0)]);      %STM evaluated at time tf
    
    %Propagate the error 
    if (noise)
        nSTM = zeros(6,3); 
        for i = 1:measurements 
             dumbSTM = reshape(S(times(i),13:end), [length(r_t0) length(r_t0)]);     %Noise state transition matrix
             nSTM = nSTM + dumbSTM.'*M*dumbSTM*[zeros(3,3); Rr];                     %Accumulated state transition matrix
        end
        nSTM = sigma^2*[zeros(6,3) [zeros(3,3); Rr]]*nSTM;                           %Accumulated state transition matrix
        nState = sigma*ns.'*nSTM;                                                    %Accumulated noise vector
    end

    %Recompute initial conditions
    switch (cost)
        case 'Position' 
            xf = S(end,7:9);                %Final positon state
            Phi = STM(1:3,4:6);             %Needed state transition matrix
            Q = Qt(1:3,1:3);                %Penalty on the state error 
            Omega = Omegat(4:6,:);          %Derivative of the state vector with respect to the impulse
            
            %Compute the STM 
            L = Omega.'*Phi.'*Q*Phi*Omega;  %Penalty on the state error 
            STM = R+L;                      %Jacobian of the constraint function
                        
        case 'State' 
            xf = S(end,7:12);               %Final state
            Phi = STM;                      %Needed state transition matrix
            Q = Qt;                         %Penalty on the state error
            Omega = Omegat;                 %Derivative of the state vector with respect to the impulse
            
            %Compute the STM
            L = Omega.'*Phi.'*Q*Phi*Omega;  %Penalty on the state error 
            STM = R+L;                      %Jacobian of the constraint function            
            
        otherwise
            error('No valid cost function was selected');
    end
        
    %Add some noise 
    if (noise)
        STM = STM + nSTM(4:6,1:3);                             %Noise state matrix
        error = xf*Q*Phi*Omega + nState;                       %Error state (deviation from the rendezvous condition)
        dV(:,iter) = pinv(STM)*error.';                        %Needed impulse
        s0(10:12) = s0(10:12)-dV(:,iter)+sigma*Rr*dV(:,iter);  %New initial conditions
        s0(7:12) = s0(7:12)+ns;                                %New noisy initial conditions
    else
        error = xf*Q*Phi*Omega;                                %Error state (deviation from the rendezvous condition)
        dV(:,iter) = STM\error.';                              %Needed impulse
        s0(10:12) = s0(10:12)-dV(:,iter);                      %New initial conditions 
    end
    
    %Reintegrate the trajectory
    [~, S] = ode113(@(t,s)nlr_model(mu, true, false, true, 'Encke', t, s), tspan, s0, options); %New trajectory
    
    %Convergence analysis 
    if (norm(error) < tol)
        GoOn = false;                        %Stop the method
    else
        iter = iter+1;                       %Update the iterations
    end
end

%Output 
St = S; 

dV0(1:3,1) = sum(dV,2);                      %Initial rendezvous impulse 
dVf(1:3,1) = -S(end,10:12).';                %Final rendezvous impulse 

St(end,10:12) = St(end,10:12)+dVf.';         %Docking burn condition

%Total maneuver metrics 
dV1(1:3,1) = dV0(:,1)+dVf(:,1);              %L1 norm of the impulses 
dV2(1) = norm(dV0(:,1))+norm(dVf(:,1));      %L2 norm of the impulses 

Pass = ~GoOn;

%Compute the error 
e = zeros(1,size(St,1));                     %Preallocation of the error vector 
for i = 1:size(St,1)
    e(i) = norm(St(i,7:12)); 
end
e(1) = norm(S0(7:12));                       %Initial error before the burn

%Compute the error figures of merit 
ISE = trapz(tspan, e.^2);
IAE = trapz(tspan, abs(e));

%% Results %% 
disp('SIMULATION RESULTS: ')
if (Pass)
    disp('   Two impulsive rendezvous was achieved');
    fprintf('   Initial impulse: %.4ei %.4ej %.4ek \n', dV0(1,1), dV0(2,1), dV0(3,1));
    fprintf('   Final impulse: %.4ei %.4ej %.4ek \n', dVf(1,1), dVf(2,1), dVf(3,1));
    fprintf('   Delta V budget (L1 norm): %.4ei %.4ej %.4ek \n', dV1(1,1), dV1(2,1), dV1(3,1));
    fprintf('   Delta V budget (L2 norm): %.4e \n', dV2(:,1));
else
    disp('    Two impulsive rendezvous was not achieved');
end

%Plot results 
figure(1) 
view(3) 
hold on
plot3(Sn(:,1), Sn(:,2), Sn(:,3)); 
plot3(S_rc(:,1), S_rc(:,2), S_rc(:,3)); 
hold off
legend('Target motion', 'Chaser motion'); 
xlabel('Synodic x coordinate');
ylabel('Synodic y coordinate');
zlabel('Synodic z coordinate');
grid on;
title('Reconstruction of the natural chaser motion');

%Plot relative phase trajectory
figure(2) 
view(3) 
plot3(St(:,7), St(:,8), St(:,9)); 
xlabel('Synodic x coordinate');
ylabel('Synodic y coordinate');
zlabel('Synodic z coordinate');
grid on;
title('Relative motion in the configuration space');

%Configuration space evolution
figure(3)
subplot(1,2,1)
hold on
plot(tspan, St(:,7)); 
plot(tspan, St(:,8)); 
plot(tspan, St(:,9)); 
hold off
xlabel('Nondimensional epoch');
ylabel('Relative configuration coordinate');
grid on;
legend('x coordinate', 'y coordinate', 'z coordinate');
title('Relative position evolution');
subplot(1,2,2)
hold on
plot(tspan, St(:,10)); 
plot(tspan, St(:,11)); 
plot(tspan, St(:,12)); 
hold off
xlabel('Nondimensional epoch');
ylabel('Relative velocity coordinate');
grid on;
legend('x velocity', 'y velocity', 'z velocity');
title('Relative velocity evolution');

%Configuration space error 
figure(4)
plot(tspan, e); 
xlabel('Nondimensional epoch');
ylabel('Absolute error');
grid on;
title('Absolute error in the configuration space (L2 norm)');

%Rendezvous animation 
if (false)
    figure(5) 
    view(3) 
    grid on;
    hold on
    plot3(St(1:index,1), St(1:index,2), St(1:index,3), 'k-.'); 
    xlabel('Synodic x coordinate');
    ylabel('Synodic y coordinate');
    zlabel('Synodic z coordinate');
    title('Rendezvous simulation');
    for i = 1:size(Sc,1)
        T = scatter3(St(i,1), St(i,2), St(i,3), 30, 'b'); 
        V = scatter3(St(i,1)+St(i,7), St(i,2)+St(i,8), St(i,3)+St(i,9), 30, 'r');

        drawnow;
        delete(T); 
        delete(V);
    end
    hold off
end