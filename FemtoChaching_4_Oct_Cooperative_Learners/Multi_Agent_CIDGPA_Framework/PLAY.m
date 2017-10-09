
function [ Conv_Actions, Game_Iterations, History_Delays, Convergence_Delays, New_Learning] = PLAY( Network_Delays, Popularities, Learning, Reward_Type, Resolution, P_Threshold   )
 
%% INPUT
% Learning: The Set of Learners as Initialised by the 'INITIALIZE_Game_Of_DGPA'.
% Network Delays: 
% Distances_Matrix: 
% Resolution: Typically 1, is the resolution step of the DGPA.
% P_Threshold: Level of probability we consider to be convergence.
%% OUTPUT
% Conv_Actions = The set of actions for each learner that the game has converged to.
% Weighted_Delays = The final weighted delay for each user.
% GAME_Delay_Performance = The history of weighted delays for each user during the GAME.

% Author: Loris Marini 
% Version: 1.0.1 
% Date: 09/09/2014

NP = size(Network_Delays,2);          % Number of content providers (BS or Helpers) in the cell
H = NP - 1;                           % Number of Helpers in the cell
N = size(Network_Delays,1);           % Number of users in the cell
M = size(Learning,1);                 % Caching capability of each Helper
F = H*M;                              % Total number of files that can be cached.
S = 1:1:F;                            % S: Space of Actions. F: How many files we can offload from the BS.
Delta = 1/(F.*Resolution);            % Resulution Step

Sources_Degree = sum(Network_Delays < Inf, 1); % Number of users connected to each provider (Helper or BS)
Users_Degree = sum(Network_Delays < Inf, 2);   % Number of providers (Helper or BS) each user is connected to.

Conv_Actions = zeros(M,H);            % The Matrix of actions to which learners converge during the game.
GAME_Positive_Feedbacks = zeros(M,H); % ....
GITER = 1;                            % Game Iteration Number.
Elapsed_Time = 0;                     % Time Initialisation.
Min_Weighted_Delay = Inf*ones(1,N);
Min_Average_Weighted_Delay = Inf*ones(1,H);
Average_Weighted_Delay = zeros(1,H);


while ~Check_Game_Convergence( Learning, P_Threshold )
    
    tic;  % Iteration Timing

    %% GAME Learners Select Files in Parallel (same time) 

    [Available_Files, New_Learning] = Learners_Select_Files( Learning );
    Learning = New_Learning;
    
   %% GAME Cumulative Feedbacks from all the users
   
    GAME_Rewards = zeros(M,H+1);   % Cumulative Rewards for all users
    GAME_Penalties = zeros(M,H+1); % Cumulative Penalties for all users
    
    switch Reward_Type
        case 'Best_File_Based_Reward'
            for n = 1:1:N
                User_Selections = User_NCA_Selection( n, S, Available_Files, Network_Delays);
                Weighted_Delay = User_Weighted_Delay( User_Selections, Popularities );
                Delay_Performance(GITER,n) = Weighted_Delay;
                User_Delays = Network_Delays(n,:);
                [ Current_Rewards, N_Rewards, Current_Penalties, N_Penalties ] = Best_File_Based_Reward( User_Delays, User_Selections, Popularities );
                GAME_Rewards = GAME_Rewards + Current_Rewards;
                GAME_Penalties = GAME_Penalties + Current_Penalties;
            end
            
        case 'Weighted_Delay_Based_Reward'
            for n = 1:1:N
                User_Selections = User_NCA_Selection( n, S, Available_Files, Network_Delays);
                Weighted_Delay = User_Weighted_Delay( User_Selections, Popularities );
                Delay_Performance(GITER,n) = Weighted_Delay;
                User_Delays = Network_Delays(n,:);
                if (Weighted_Delay < Min_Weighted_Delay(n))
                    Min_Weighted_Delay(n) = Weighted_Delay;
                end
                if( GITER == 1)
                    Current_Minima = Inf;
                elseif (GITER > 1)
                    Current_Minima = Min_Weighted_Delay(n);
                end
                [ Current_Rewards, N_Rewards, Current_Penalties, N_Penalties ]...
                    = Weighted_Delay_Based_Reward( User_Delays, User_Selections, Weighted_Delay, Current_Minima , Popularities );  
                GAME_Rewards = GAME_Rewards + Current_Rewards;
                GAME_Penalties = GAME_Penalties + Current_Penalties;
            end
        case 'Average_Weighted_Delay_Based_Reward'
            
            Tot_Rewards = zeros(M,H+1,N);
            Tot_Penalties = zeros(M,H+1,N);
            
            for n = 1:1:N
                User_Selections(n,:,:,:) = User_NCA_Selection( n, S, Available_Files, Network_Delays);
                This_User_Selections = squeeze(User_Selections(n,:,:,:));
                Weighted_Delay(n) = User_Weighted_Delay( This_User_Selections, Popularities );
                Delay_Performance(GITER,n) = Weighted_Delay(n);
                User_Delays = Network_Delays(n,:);
                [ Current_Rewards, N_Rewards, Current_Penalties, N_Penalties ] = Best_File_Based_Reward( User_Delays, This_User_Selections, Popularities );
                Tot_Rewards(:,:,n) = Current_Rewards;
                Tot_Penalties(:,:,n) = Current_Penalties;
            end
            
            for j=1:1:H
                % Take only the users connected to the learner (j,k)
                Who_to_Average = Network_Delays(:,j) ~= Inf;
                Average_Weighted_Delay(j) = sum( Weighted_Delay(Who_to_Average)) / sum(Who_to_Average);
                
                if (Average_Weighted_Delay(j) <= Min_Average_Weighted_Delay(j) )
                    
                    Min_Average_Weighted_Delay(j) = Average_Weighted_Delay(j);
                    GAME_Rewards(:,j) = GAME_Rewards(:,j) + sum( squeeze( Tot_Rewards(:,j,:) ),2);
                    GAME_Penalties(:,j) = GAME_Penalties(:,j) + sum( squeeze( Tot_Penalties(:,j,:) ),2);
                else
                    GAME_Rewards(:,j) = GAME_Rewards(:,j);
                    GAME_Penalties(:,j) = GAME_Penalties(:,j) + sum( squeeze( Tot_Rewards(:,j,:) ),2) + sum( squeeze( Tot_Penalties(:,j,:) ),2);
                end
            end 
            History_Of_Average_Weighted_Delays(GITER,:) = Average_Weighted_Delay;

    end

    %% INI Learners Determine the Environment Feedback Democratically

    [ Learning, GAME_Positive_Feedbacks ] = Determine_Environment_Feedback( Learning, GAME_Rewards, GAME_Penalties, GAME_Positive_Feedbacks);
       
     
    %% GAME Probabilities Vectors Update.
    
    [ Updated_Learning, Updated_Conv_Actions ] = Move_P_Vector( Conv_Actions, Learning, Delta, P_Threshold);
    Learning = Updated_Learning;
    Conv_Actions = Updated_Conv_Actions;
    
    %% Iteration Timing
    Time = toc;
    Elapsed_Time = Elapsed_Time + Time;
    Average_Time = Elapsed_Time/GITER;
    %disp(['This is iteration number ' num2str(GITER) '. The Average Time per iteration is: ' num2str(Average_Time) '.'] );
    
      GITER = GITER + 1;   
end 

Game_Iterations = GITER - 1;
New_Learning = Learning; 

%{
% VISUAL OUTPUT
disp('-------------------------------------------------------------------');
disp('=================== Convergence COMPLETE. ======================');
disp('-------------------------------------------------------------------');

 switch Reward_Type
        case 'Best_File_Based_Reward'
            
            disp(Reward_Type);
            disp(['The converged weighted delays are: ' num2str(Delay_Performance(GITER-1,:)) '.']);
            disp(['The Average Weighted Delay among all the users is: ' num2str(sum( Delay_Performance(GITER-1,:) )./N) '.']);
            disp(['The game with ' num2str(M*H) ' players (that is file memories) converged after ' num2str(GITER-1) ' iterations.']);
            
        case 'Weighted_Delay_Based_Reward'
            
            disp(Reward_Type);
            disp(['The converged weighted delays are: ' num2str(Delay_Performance(GITER-1,:)) '.']);
            disp(['The Average Weighted Delay among all the users is: ' num2str(sum(Delay_Performance(GITER-1,:))./N) '.']);
            disp(['The game with ' num2str(M*H) ' players (that is file memories) converged after ' num2str(GITER-1) ' iterations.']);
            
        case 'Average_Weighted_Delay_Based_Reward'
            
            disp(Reward_Type);
            disp(['The converged weighted delays are: ' num2str(Delay_Performance(GITER-1,:)) '.']);
            disp(['The Min_Average_Weighted_Delays, at convergence are : ' num2str(Min_Average_Weighted_Delay) '.']);
            disp(['The game with ' num2str(M*H) ' players (that is file memories) converged after ' num2str(GITER-1) ' iterations.']);
 end

%}
%% Variables Output:

switch Reward_Type
        case 'Best_File_Based_Reward'       
            History_Delays = Delay_Performance;
            Convergence_Delays = Delay_Performance(end,:);
            
        case 'Weighted_Delay_Based_Reward'
            History_Delays = Delay_Performance;
            Convergence_Delays = Delay_Performance(end,:);
            
        case 'Average_Weighted_Delay_Based_Reward'    
            History_Delays = History_Of_Average_Weighted_Delays;
            Convergence_Delays = History_Of_Average_Weighted_Delays(end,:);
end
 
end
