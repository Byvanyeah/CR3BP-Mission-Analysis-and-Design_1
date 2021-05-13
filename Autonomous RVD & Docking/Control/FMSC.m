%% Autonomous RVD and docking in the CR3BP %% 
% Sergio Cuevas del Valle % 
% 25/04/21 % 

%% GNC 10: Floquet Mode Safe Control %% 
% This script provides an interface to test the Floquet mode strategy for collision avoidance maneuvers. 

% The relative motion of two spacecraft in the same halo orbit (closing and RVD phase) around L1 in the
% Earth-Moon system is analyzed.

% Units are non-dimensional and solutions are expressed in the Lagrange
% points reference frame as defined by Howell, 1984.

%% Set up %%
%Set up graphics 
set_graphics();

%Integration tolerances (ode113)
options = odeset('RelTol', 2.25e-14, 'AbsTol', 1e-22);  

%% Contants and initial data %% 
%Phase space dimension 
n = 6; 

%Time span 
dt = 1e-3;                          %Time step
tspan = 0:dt:2*pi;                  %Integration time span

%CR3BP constants 
mu = 0.0121505;                     %Earth-Moon reduced gravitational parameter
L = libration_points(mu);           %System libration points
Lem = 384400e3;                     %Mean distance from the Earth to the Moon

%Differential corrector set up
nodes = 10;                         %Number of nodes for the multiple shooting corrector
maxIter = 20;                       %Maximum number of iterations
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
T = target_orbit.Period;

%Continuate the first halo orbit to locate the chaser spacecraft
Bif_tol = 1e-2;                                             %Bifucartion tolerance on the stability index
num = 2;                                                    %Number of orbits to continuate
method = 'SPC';                                             %Type of continuation method (Single-Parameter Continuation)
algorithm = {'Energy', NaN};                                %Type of SPC algorithm (on period or on energy)
object = {'Orbit', halo_seed, target_orbit.Period};         %Object and characteristics to continuate
corrector = 'Plane Symmetric';                              %Differential corrector method
direction = 1;                                              %Direction to continuate (to the Earth)
setup = [mu maxIter tol direction];                         %General setup

[chaser_seed, state_PA] = continuation(num, method, algorithm, object, corrector, setup);
[chaser_orbit, ~] = differential_correction('Plane Symmetric', mu, chaser_seed.Seeds(2,:), maxIter, tol);

%% Modelling in the synodic frame %%
r_t0 = target_orbit.Trajectory(100,1:6);                    %Initial target conditions
r_c0 = target_orbit.Trajectory(1,1:6);                      %Initial chaser conditions 
rho0 = r_c0-r_t0;                                           %Initial relative conditions
s0 = [r_t0 rho0].';                                         %Initial conditions of the target and the relative state
Phi = eye(length(r_t0));                                    %Initial STM
Phi = reshape(Phi, [length(r_t0)^2 1]);                     %Initial STM
s0 = [s0; Phi];                                             %Initial conditions

%Integration of the model
[t, S] = ode113(@(t,s)nlr_model(mu, true, false, true, 'Encke', t, s), tspan, s0, options);
Sn = S;                

%Reconstructed chaser motion 
S_rc = S(:,1:6)+S(:,7:12);                                  %Reconstructed chaser motion via Encke method

%% Obstacle in the relative phase space 
%Obstacle definition in space and time
index(1) = randi([1 2000]);                 %Time location of the collision 
index(2) = 20;                              %Detection time
so = [S(index(1),7:9) 0 0 0];               %Phase space state of the object
R = 5e-4;                                   %Radius of the CA sphere
[xo, yo, zo] = sphere;                      %Collision avoidance sphere
xo = R*xo;
yo = R*yo;
zo = R*zo;

%Safety parameters 
Q = eye(3);                                 %Safety ellipsoid size to avoid the collision

%% GNC: FMSC %% 
%Select the collision time (randomly)
TOC = tspan(index(1));                  %Time of collision
constraint.Constrained = true;         %No constraints on the maneuver
constraint.SafeDistance = 1e-6;         %Safety distance at the collision time

[Sc, dV, tm] = FMSC_control(mu, pi, so, eye(3), S(1,1:12), 1e-5, constraint, 'Worst');

Sc = [S(1:index(2),1:12); Sc(:,1:12)];  %Complete trajectory
ScCAM = Sc(:,1:3)+Sc(:,7:9);            %Chaser CAM trajectory

%Relative trajectory to the object
Scr(:,7:12) = Sc(:,7:12)-repmat(so, size(Sc,1), 1);
    
%% Results %% 
%Plot results 
figure(1) 
view(3) 
hold on 
%surf(xo+so(1),yo+so(2),zo+so(3));
plot3(Scr(:,7), Scr(:,8), Scr(:,9), 'b'); 
%plot3(S(:,7), S(:,8), S(:,9), 'r'); 
hold off
xlabel('Synodic x coordinate');
ylabel('Synodic y coordinate');
zlabel('Synodic z coordinate');
grid on;
legend('Colliding object', 'CAM trajectory', 'Nominal trajectory');
title('Relative CAM motion in the configuration space');
%%
figure(2) 
view(3) 
hold on 
surf(xo+so(1)+S(index(1),1),yo+so(2)+S(index(1),2),zo+so(3)+S(index(1),3));
plot3(ScCAM(:,1), ScCAM(:,2), ScCAM(:,3), 'b'); 
plot3(S(:,1), S(:,2), S(:,3), 'r'); 
hold off
xlabel('Synodic x coordinate');
ylabel('Synodic y coordinate');
zlabel('Synodic z coordinate');
grid on;
legend('Colliding object', 'CAM trajectory', 'Nominal trajectory');
title('Absolute CAM motion in the configuration space');

%Configuration space evolution
figure(3)
subplot(1,2,1)
hold on
plot(tspan(1:size(Sc,1)), Sc(:,7)); 
plot(tspan(1:size(Sc,1)), Sc(:,8)); 
plot(tspan(1:size(Sc,1)), Sc(:,9)); 
hold off
xlabel('Nondimensional epoch');
ylabel('Relative configuration coordinate');
grid on;
legend('x coordinate', 'y coordinate', 'z coordinate');
title('Relative position evolution');
subplot(1,2,2)
hold on
plot(tspan(1:size(Sc,1)), Sc(:,10)); 
plot(tspan(1:size(Sc,1)), Sc(:,11)); 
plot(tspan(1:size(Sc,1)), Sc(:,12)); 
hold off
xlabel('Nondimensional epoch');
ylabel('Relative velocity coordinate');
grid on;
legend('x velocity', 'y velocity', 'z velocity');
title('Relative velocity evolution');

%% Old code
% %% GNC: FMSC %%
% %Detect the object at a random reasonable time (critical parameter)
% index(2) = randi([1 fix(index(1)/2)]);                      %Collision detection time
% 
% %Analyze the trajectory and compute each maneuver
% tspanc = 0:dt:tspan(index(1))-tspan(index(2));              %Integration time
% 
% %Preallocation 
% J = zeros(2,length(tspanc)-1);                              %Cost function to analyze
% dV = zeros(3,length(tspanc)-1);                             %Velocity impulses all along the look ahead time arc
% 
% %Select the restriction level of the CAM 
% constrained = true;                                         %Safety distance constraint
% restriction = 'Worst';                                      %Collision risk
% lambda(1) = 1e-1;                                           %Safety distance
% lambda(2) = 1e-1;                                           %Safety distance
% 
%  for i = 1:length(tspanc)-1
%     %Shrink the look ahead time 
%     atime = tspanc(i:end);
%     
%     %Compute the Floquet modes at each time instant 
%     Monodromy = reshape(S(index(1),13:end), [6 6]);                           %State transition matrix at each instant        
%     [E, sigma] = eig(Monodromy);                                              %Eigenspectrum of the STM 
%     Phi = Monodromy*reshape(S(index(2)+(i-1),13:end), [6 6])^(-1);            %Relative STM
%     
%     for j = 1:size(E,2)
%         if (constrained)
%             E(:,j) = sigma(j,j)*E(:,j);
%         else
%             E(:,j) = exp(-tspan(index(2)+(i-1))/tspan(index(1))*log(sigma(j,j)))*E(:,j);
%         end
%     end
%     
%     %Compute the maneuver
%     switch (restriction) 
%         case 'Worst'
%             if (constrained)
%                 safeS = lambda(1)*E(:,1);                                      %Safety constraint
%                 STM = Phi(:,4:6);                                              %Correction matrix
%                 error = safeS-S(end,7:12).';                                   %Error in the unstable direction only
%                 maneuver = pinv(STM)*error;                                    %Needed maneuver 
%                 dV(:,i) = maneuver(end-2:end);                                 %Needed change in velocity
%             else
%                 w = [0; 1; 1; 1];                                              %Some random vector offerint triaxial control
%                 STM = [E(:,1) -[zeros(3,3); eye(3)]];                          %Linear application
%                 error = lambda(1)*rand(6,1);                                   %State error vector
%                 maneuver = pinv(STM)*error;                                    %Needed maneuver
%                 dV(:,i) = real(maneuver(end-2:end));                           %Needed change in velocity
%             end
%         case 'Best'
%             if (constrained)
%                 safeS = lambda(1)*E(:,1)+lambda(2).*E(:,3:end);                %Safety constraint
%                 STM = Phi(:,4:6);                                              %Correction matrix
%                 error = safeS-S(end,7:12).';                                   %Error in the unstable direction only
%                 maneuver = pinv(STM)*error;                                    %Needed maneuver 
%                 dV(:,i) = maneuver(end-2:end);                                 %Needed change in velocity
%             else
%                 STM = [E(:,1) E(:,3:end) -[zeros(3,3); eye(3)]];               %Linear application
%                 error = 1e-3*rand(6,1);                                        %State error vector
%                 maneuver = STM.'*(STM*STM.')^(-1)*error;                       %Needed maneuver
%                 dV(:,i) = real(maneuver(end-2:end));                           %Needed change in velocity
%             end
%         otherwise
%             error('No valid case was selected');
%     end
%     
%     %Integrate the trajectory 
%     s0 = S(index(2)+(i-1),1:12);            %Initial conditions
%     s0(10:12) = s0(10:12)+real(dV(:,i)).';  %Update initial conditions with the velocity change
%     
%     [~, s] = ode113(@(t,s)nlr_model(mu, true, false, false, 'Encke', t, s), atime, s0, options);       %Integrate the trajectory
%     
%     %Evaluate the cost function
%     J(1,i) = (1/2)*(s(end,7:9)-so(1,1:3))*Q*(s(end,7:9)-so(1,1:3)).';
%     J(2,i) = norm(maneuver)+(1/2)*s(end,7:12)*s(end,7:12).';  
%  end
% 
% %Select the safest trajectory 
% tol = 1e-4;
% best = size(J,2); 
% for i = 1:size(J,2)
%     if (J(1,i)-J(1,best) > tol)
%         best = i;
%     elseif (J(1,i)-J(1,best) < tol)
%         %Do nothing, just the other extreme case
%     else
%         %Minimize the second cost function 
%         if (J(2,i) < J(2,best))
%             best = i;
%         end
%     end
% end
% bestCAM.Impulse = dV(:,best);                          %Needed impulse
% bestCAM.Cost = J(1,best);                              %Cost function
% 
% atime = tspan(index(2)+best(end):index(2)+best+20);    %CAM integration time
% s0 = S(index(2)+(best-1),1:12);                        %Initial conditions
% s0(10:12) = s0(10:12)+dV(:,best).';                    %Update initial conditions with the velocity change
% 
% %Integrate the CAM trajectory
% [~, SCAM] = ode113(@(t,s)nlr_model(mu, true, false, false, 'Encke', t, s), atime, s0, options); 
% SCAM = [S(1:index(2)+(best-1),1:12); SCAM];
% ScCAM = SCAM(:,1:6)+SCAM(:,7:12);