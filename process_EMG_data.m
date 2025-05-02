clear
close all
warning('off','MATLAB:nargchk:deprecated'); % turn this warning off, or else it will be issued for "crossing.m" and I don't feel like fixing "crossing.m" right now.  You could say I'm cross about having to fix it.  Ha!

% set parameter source:
% 0 -> use hard-coded parameters below
% 1 -> read from file "params.txt"
param_source = 1;

% set plot level:
% 0 -> no plots
% 1 -> only individual EMG variables
% 2 -> only L/R pairs
% 3 -> all
plot_level = 3;

% set prompt:
% 0 -> do not prompt for input folder (use default of 'C:\Users\TJ Univ\Documents\LE testing\Subject 6\Processed_Data\Exported Data', e.g. for testing)
% 1 -> prompt for input folder (typical)
% 2 -> use test folder (see below)
source_folder = 0;

% figure out which computer you're running on
[~, hostname] = system('hostname');
if strfind(hostname, 'jfalesi-PC') % if testing on my PC
    input_folder = 'C:\Users\jfalesi\Documents\Jamie_Local\Projects\Therese Cycling\Data\P6 Processed Data\Exported Data';
    plot_label_folder = 'C:\Users\jfalesi\Documents\Jamie_Local\Projects\Therese Cycling\Data'; % location of plot label file on my computer
    param_file = 'C:\Users\jfalesi\Documents\Jamie_Local\Projects\Therese Cycling\Data\params.xlsx'; % path to parameters file on my computer
    
else % probably running on lab PC
    if source_folder == 1 % prompt for exported data folder
        input_folder = uigetdir('C:\Users\TJ Univ\Documents\LE testing\', 'Select subject Exported Data folder.'); % prompt for folder containing exported data folders
    elseif source_folder == 0 % set to default for processing
        input_folder = 'C:\Users\TJ Univ\Documents\LE testing\Subject 6\Processed_Data\Exported Data'; % set to default exported data folder
    elseif source_folder == 2 % use testing folder
        input_folder = 'C:\Users\TJ Univ\Documents\LE testing\Subject 6\Processed_Data\Test Exported Data'; % set to default exported data folder
    end
    plot_label_folder = 'C:\Users\TJ Univ\Documents\LE testing\Plot Labels'; % location of plot label file on lab computer
    param_file = 'C:\Users\TJ Univ\Documents\LE testing\Params\params.xlsx'; % path to parameters file on my computer
end

% set params
if param_source
    % load from file
    params = readtable(param_file);
    variables = params.(1);
    params.Properties.RowNames = variables;
    bandpass_low = params.Value('bandpass_low');
    bandpass_high = params.Value('bandpass_high');
    lowpass_cutoff = params.Value('lowpass_cutoff');
    window_size_ms = params.Value('moving_avg_window');
    sampling_rate = params.Value('sampling_rate');
else
    bandpass_low = 20; %Hz
    bandpass_high = 350; %Hz
    lowpass_cutoff = 10; %Hz
    window_size_ms = 25; %ms
    sampling_rate = 1200; %Hz
end

f_nyquist = sampling_rate/2;
time_step = 1/sampling_rate;
window_size_samples = sampling_rate*window_size_ms;

% Load lables from the EMG data labels file
plot_label_file = 'EMG_data_labels.txt';
fID = fopen(fullfile(plot_label_folder,plot_label_file));

if fID > 0 % if file exists
    formatSpec = '%s%s%s%f%f%s';
    line1 = fgetl(fID); % skip first line
    rest = textscan(fID, formatSpec, 'Delimiter', '\t');
    axis_pos = rest{2}; % positive region label
    axis_neg = rest{3}; % negative region label
    low_limit = rest{4}; % minimum y-axis value for plot
    high_limit = rest{5}; % maximum y-axis value for plot
    units = rest{6}; % units for this particular variable (used in y-axis label)
else
    error('EMG_data_labels.txt file not found.  Should be at "C:\Users\TJ Univ\Documents\LE testing\Plot Labels".')
end

dirs = dir(input_folder);
dirs(1:2) = []; % skip "." and ".."

% sort directories by date
[~, sordid_idx] = sort([dirs.datenum]);
sordid_dirs = dirs(sordid_idx);
num_dirs = length(dirs);

%% LOAD AND PLOT ALL TRIALS
% Load Baseline EMG Data
baseline_EMG_file = fullfile(input_folder, 'Quiet_EMG_means.txt');
BL_EMG = readtable(baseline_EMG_file);

% iterate over trial folders
for i = 1:num_dirs
    cur_dir = sordid_dirs(i);
    if cur_dir.isdir % check if it's a directory
        % if it's a directory, assume it contains valid exported data files
        % (.trc file with marker data and .txt file with kinematic data)
        cur_dir_name = cur_dir.name;
        cur_path = fullfile(input_folder, cur_dir_name);
        disp(['Processing ', cur_dir_name]);
        
        % build output folder
        output_folder = fullfile(cur_path, 'plots');
        if ~exist(output_folder, 'dir')
            mkdir(output_folder);
        end
        
        %% LOAD MARKER DATA to find revolutions (EMG data will be averaged over revolutions)
        % get the .trc file (the marker data)
        trc_file = dir([cur_path, '\*.trc']);
        trc_file_path = fullfile(cur_path, trc_file.name);
        %         try
        fID = fopen(trc_file_path);
        
        % initialize marker data structure
        marker_data = struct();
        
        if fID > 0 % if file was successfully opened
            
            formatSpec = '%s';
            line1 = fgetl(fID); % skip first line
            line2 = fgetl(fID); % skip second line
            line3 = fgetl(fID); % skip third line
            line4 = fgetl(fID); % read headers (why is this a 1x1 cell of cells)?
            marker_headers = textscan(line4, '%s', 'Delimiter', '\t', 'MultipleDelimsAsOne',1);
            marker_headers = marker_headers{1,1};
            line5 = fgetl(fID); % skip 5th line
            line6 = fgetl(fID); % skip 6th line
            num_hdrs = length(marker_headers);
            
            % Create variable lookup table (column number -> variable name) and reverse lookup table (variable name -> column no)
            % Former is used to determine the current variable as we iterate over columns. The latter is not currently used.
            marker_lookup = {};
            rev_marker_lookup = containers.Map;
            for col_num=1:num_hdrs
                cur_hdr = marker_headers{col_num};
                marker_lookup{col_num,1} = convert_funky_chars(cur_hdr);
                rev_marker_lookup(cur_hdr) = col_num;
            end
            
            % compute the number of columns
            num_cols = 2 + (num_hdrs - 2)*3; % first column is frame #, second column is time. The rest of the columns are 3D variables.  For each 3D header in num_hdrs, there are three columns of data (x,y,z).
            
            % iterate over the remaining rows, populating marker_data struct with marker data
            line_num = 1; % we have to use a while loop to determine when we get to the end of the file, so we need a counter.
            while ~feof(fID)
                cur_line_all = fgetl(fID);
                cur_line = textscan(cur_line_all,'%f', num_cols, 'Delimiter', '\t','MultipleDelimsAsOne', 0);
                cur_line = cur_line{1,1};
                num_line_cols = length(cur_line);
                %             disp(['Line num ', num2str(line_num)]); % debug
                if ~isempty(cur_line) % check if the line is empty
                    col_num=1; % initialize column number, since we're about to iterate over them
                    var_num=1; % initialize variable number, since we're REALLY about to iterate over them.  I promise.
                    while col_num<=num_cols % iterate over columns (but really over variables)
                        cur_var = marker_lookup{var_num,1}; % get current variable name
                        if col_num<3 % if we're on one of the first two columns (FrameNum or Time)
                            cur_val = cur_line(col_num); % get current value
                            marker_data.(cur_var)(line_num) = cur_val; % add it to marker_data
                            % disp(['Line num ', num2str(line_num), '; Col num = ', num2str(col_num), '; Var num = ', num2str(var_num), '; Cur var = ', cur_var, '; Cur val = ', num2str(cur_val)])
                            col_num = col_num + 1; % iterate by one, since this is a 1D variable
                        else % we're on a 3D variable
                            % disp(['Col ', num2str(col_num), ' Row ', num2str(var_num)]);
                            if col_num > num_line_cols % this will occur if there is no data for the last marker (V_T8)
                                marker_data.(cur_var)(line_num,1) = NaN; % x-value
                                marker_data.(cur_var)(line_num,2) = NaN; % y-value
                                marker_data.(cur_var)(line_num,3) = NaN; % z-value
                            else
                                marker_data.(cur_var)(line_num,1) = cur_line(col_num); % x-value
                                marker_data.(cur_var)(line_num,2) = cur_line(col_num + 1); % y-value
                                marker_data.(cur_var)(line_num,3) = cur_line(col_num + 2); % z-value
                                % disp(['Line num ', num2str(line_num), '; Col num = ', num2str(col_num), '; Var num = ', num2str(var_num), '; Cur var = ', cur_var, '; Cur vals = ', num2str(cur_line(col_num)), ', ', num2str(cur_line(col_num+1)), ', ', num2str(cur_line(col_num+2))])
                            end
                            col_num = col_num + 3; % iterate by 3, since it's a 3D variable
                        end
                        var_num = var_num + 1; % next variable
                    end
                end
                line_num = line_num + 1; % next line
            end
            % if you figure out an easier way to load allz teh dataz, let me know jfalesi@hotmail.com
        else % error opening file
            error_string = ['Can''t find .trc file in "', cur_path, '".']; % all your base are belong to us
            disp(error_string);
            continue;
        end
        %         catch ME % probably caused by bad filename
        %             error_string = ['Error opening file "', trc_file.name, '": ', ME.message];
        %             disp(error_string);
        %             continue; % skip this folder, go to next one
        %             % all marker data is now loaded
        %         end
        
        %% FIND REVOLUTIONS from marker data (will not be televised)
        % Now we shall determine the start- and end- frames for each cycle crank revolution.
        %         try
        % Part 1) Compute crank angles
        % Crank angle is defined as the angle that the right crank makes relative to the vertical axis, with zero defined as top-dead-center (i.e. when the right pedal at its highest point)
        % To compute crank angle, we will project the vector from the right pedal to the left pedal into the x-z plane (vertical plane along the length of the bike, or the sagittal plane in
        %  biomechanics-speak). We then compute the angle this vector makes with the z-axis using - I dunno, trigonometry or something.
        R_crank = marker_data.R_crank;
        L_crank = marker_data.L_crank;
        crank_vector_x = R_crank(:,1) - L_crank(:,1); % x-component of the vector from the left crank to the right crank
        crank_vector_z = R_crank(:,3) - L_crank(:,3); % z-component of the vector from the left crank to the right crank
        crank_length = sqrt(crank_vector_x.^2 + crank_vector_z.^2)/2;
        sin_crank_angle = crank_vector_x./crank_length; % trigonometry or something
        cos_crank_angle = crank_vector_z./crank_length; % trigonometry or something
        crank_angle = atan2d(crank_vector_x, crank_vector_z); % trigonometry or something
        % ok, so we used the pythagorean theorem to get the length of the projection of said vector in the sagittal plane, then computed the sin and cos of the crank angle for further use.  Then we used the
        % definition of tan(theta) to get the angle between the vector and the z-axis.  You might need to draw a diagram to verify this for yourself.
        
        % Part 2) Get zero crossings
        % Now we need the frame numbers (or the array indices, which are the same thing) of the times that correspond as close as possible to crank angles of zero.  Since we defined the crank angle relative to Right
        % Pedal's top-dead-center, these are the times at which the right pedal crosses the +z axis.  These are also the times that try men's souls. The simplest way to do this is to get the indices at which the Sin of the crank angle crosses zero (sin = 0 corresponds to TDC and BDC of the right pedal).
        % This handy little function called "crossing" will do it for us.
        [~, ~, ~, cross_idx, ~] = crossing(sin_crank_angle, [], 0, 'linear');
        
        % Now filter out the indices that correspond to BDC (get the ones that correspond to crank_angle = 0, i.e. where cos(crank_angle) > 0)
        TDC_idx = cross_idx(cos_crank_angle(cross_idx)>0);
        % TDC_idx are now the frame numbers in which the right pedal is as close as possible to TDC. TDC_idx are the indices that indicate the "zero-angle" crossings.
        
        % Plot stuff for sanity's sake
        fig = figure;
        x_axis = 0:time_step:length(R_crank)/sampling_rate-time_step;
        yyaxis left
        plot(x_axis, R_crank(:,3));
        ylabel('R Crank Height (mm)');
        yyaxis right
        plot(x_axis, crank_angle);
        ylabel('R Crank Angle (deg)');
        vline(TDC_idx/sampling_rate);
        hline(0);
        xlabel('Time (s)');
        title_string = ['Visual Depiction of Revolution Detection for ', strrep(cur_dir_name,'_', ' ')];
        title(title_string);
        fig_file = [output_folder, '\', title_string];
        print(fig_file, '-dpng');
        savefig(fig_file);
        close(fig);
        %         catch ME %
        %             error_string = ['Error finding revolutions in file "', trc_file.name, '": ', ME.message];
        %             disp(error_string);
        %             continue; % skip this folder, go to next one
        %         end
        %% LOAD EMG DATA
        % Now we load the EMG data so they can be plotted vs. crank angle and averaged over crank revolutions.
        %         try
        % get the EMG file
        EMG_file = dir([cur_path, '\*EMG.txt']);
        EMG_file_path = fullfile(cur_path, EMG_file.name);
        fID = fopen(EMG_file_path);
        
        % set parameters
        num_vars =16;
        EMG_data = struct();
        
        if fID > 0 % if file is successfully opened
            formatSpec = '%s';
            line1 = fgetl(fID); % skip first line
            line2 = fgetl(fID); % skip second line
            line3 = fgetl(fID); % get headers
            EMG_headers = textscan(line3,formatSpec,num_vars,'Delimiter', '\t','MultipleDelimsAsOne', 1); % why is this a 1x1 cell of cells?
            EMG_headers = EMG_headers{1,1}; % that's better
            line4 = fgetl(fID); % skip 4th line
            
            % create vector (ok, cell array) of variable names
            var_names{1,1} = 'Frame_Num'; % first column is Frame Number
            for col_num=1:num_vars
                cur_hdr = EMG_headers{col_num};
                var_names{col_num+1,1} = convert_funky_chars(cur_hdr);
            end
            
            % Iterate over columns.  This time, each column corresponds to a single variable, so there's no column-skipping shenanigans.
            num_cols = num_vars+1;
            line_num = 1;
            while ~feof(fID)
                cur_line = textscan(fID,'%f',num_cols,'Delimiter', '\t','MultipleDelimsAsOne', 0);
                cur_line = cur_line{1,1};
                if ~isempty(cur_line)
                    for j = 1:num_cols
                        cur_var = var_names{j};
                        EMG_data.(cur_var)(line_num,1) = cur_line(j);
                    end
                end
                line_num = line_num + 1; % see, shenaniganless.
            end
        else % error opening file
            error_string = ['Can''t find EMG file in "', cur_path, '".'];
            disp(error_string);
            continue;
        end
        %         catch ME %
        %             error_string = ['Error opening EMG file "', EMG_file.name, '": ', ME.message];
        %             disp(error_string);
        %             continue; % skip this folder, go to next one
        %             % all marker data is now loaded
        %         end
        % EMG data is now loaded
        
        %% Filter EMG Data
        for k = 2:length(var_names)
            cur_hdr = var_names{k};
            cur_data = EMG_data.(cur_hdr);
            % 4th order butterworth bandpass filter w/zero phase offset
            BP_data = bandPassFilterData(cur_data, bandpass_low, bandpass_high, time_step, 0, output_folder);
            % rectify
            rect_data = abs(BP_data);
            % low-pass filter
            LP_data = lowpassFilterData(rect_data, lowpass_cutoff, time_step, 0, output_folder);
            % moving-window-average
            mavg_data = movmean(LP_data, window_size_samples);
            % save over raw data
            EMG_data.(cur_hdr) = mavg_data;
            
            % Plot filtered EMG data along with TDC IDXs to visualize how the EMG data should be sliced into revolutions
            fig = figure;
            hold on;
            plot(x_axis, cur_data);
            plot(x_axis, mavg_data);
            vline(TDC_idx/sampling_rate);
            legend('Raw Data', 'Processed Data');
            filename = get_filename(EMG_file);
            title_string = strrep([filename, ' ', cur_hdr, ' EMG Data'], '_', ' ');
            title(title_string);
            fig_file = [output_folder, '\', title_string];
            print(fig_file, '-dpng');
            savefig(fig_file);
            close(fig);
            
            if plot_level > 0
                % plot the steps
                fig = figure;
                x_data = getTime(cur_data, time_step);
                plot(x_data, cur_data-mean(cur_data));
                hold on;
                plot(x_data, BP_data);
                plot(x_data, rect_data);
                plot(x_data, LP_data);
                plot(x_data, mavg_data);
                [filename,~,~] = fileparts(EMG_file.name);
                title_string = strrep(strcat(filename, ' ', cur_hdr, ' EMG Processing Steps'), '_', ' ');
                title(title_string);
                xlabel('Time (S)');
                ylabel('Signal Level (V)');
                raw_legend = 'Raw';
                BP_legend = strcat('Bandpass Filtered @ ', num2str(bandpass_low), '-', num2str(bandpass_high), ' Hz');
                rect_legend = 'Rectified';
                filt_legend = strcat('Lowpass Filtered @ ', num2str(lowpass_cutoff), ' Hz');
                mavg_legend = strcat('Moving-Average @ ', num2str(window_size_ms), 'ms Window');
                legend(raw_legend, BP_legend, rect_legend, filt_legend, mavg_legend);
                fig_file = [output_folder, '\', title_string];
                print(fig_file, '-dpng');
                savefig(fig_file);
                close(fig);
            end
            %             % Plot frequency spectrums
            %             % Raw PSD
            %             signal = rev_means;
            %             N = length(signal);
            %             freqs = 0:sampling_rate/N:f_nyquist;
            %             file_name = strsplit(trc_file.name, '1-');
            %             fig_title = strrep([file_name{1}, ' ', var_name], '_', ' ');
            %             fig = figure;
            %             hold on;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             N_2 = ceil(N/2);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             title(fig_title);
            %             xlabel('Frequency (Hz)');
            %             ylabel('Power (Watts)');
            %             % BP PSD
            %             signal = BP_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             % rect_PSD
            %             signal = rect_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             % filt PSD
            %             signal = filt_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             % mavg PSD
            %             signal = mavg_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             legend(raw_legend, BP_legend, rect_legend, filt_legend, mavg_legend);
            %             savePlot(fig, output_folder, fig_title);
            %             close;
            
        end
        
        
        
        %% SLICE EMG DATA INTO REVOLUTIONS
        % Now we have to separate all the EMG variables into individual revolutions so we can plot and average them relative to crank angle.
        %         try
        num_revs = length(TDC_idx) - 1; % Get the number of complete revolutions (number of zero-crossings minus one)
        revs = struct();
        var_revs = struct();
        angle_interp_grid = transpose(0:1:360); % we will interpolate EMG data over 360 degrees, assuming constant cadence (cadence is pretty constant - these are serious cyclers)
        cur_EMG_data = zeros(1,1);
        
        for rev_no = 1:num_revs % for each revolution,
            rev_start_frame = TDC_idx(rev_no); % get the frame number of the first angle greater than zero
            rev_end_frame = TDC_idx(rev_no + 1) - 1; % get the frame number of the last angle less than 360
            revs(rev_no).start_frame = rev_start_frame; % save these for posterity
            revs(rev_no).end_frame = rev_end_frame; % save these for posterity
            num_frames = rev_end_frame - rev_start_frame+1; % compute the number of frames in this revolution
            deg_per_frame = 360 / num_frames; % compute the average number of degrees traversed per frame
            angle_grid = transpose(0:deg_per_frame:360);%-deg_per_frame); % create an angle grid using the average degrees per frame as the angle increment (this is where the constant-cadence assumption is baked into the analysis)
            for var_no = 1:num_vars % for each variable,
                var_name = var_names{var_no+1}; % skip "Frame_Num"
                cur_EMG_data = EMG_data.(var_name)(rev_start_frame:rev_end_frame+1); % slice the data between the current revolution's start and end frames (add the first frame of the next revolution so we can interpolate to 360)
      a          revs(rev_no).(var_name)(1:num_frames+1) = cur_EMG_data; % save this data in a structure
                %                     cur_EMG_data(end+1) = cur_EMG_data(1); % set the last data point equal to the first data point (I mean, it IS a cirle after all)
                current_rev = interp1(angle_grid, cur_EMG_data, angle_interp_grid); % interpolate the current variable over the interpolation grid (I just realized I could wait until all variables are loaded for the given revolution and call interp1 on the array of variables, but oh well)
                revs_over_360.(var_name)(1:361,rev_no) = current_rev; % save in a new structure
            end
        end
        %         catch ME %
        %             error_string = ['Error slicing into revs for EMG file "', EMG_file.name, '": ', ME.message];
        %             disp(error_string);
        %             continue; % skip this folder, go to next one
        %             % all marker data is now loaded
        %         end
        
        % create file to write averaged data to
        mean_data_filename = strcat(replace(EMG_file.name, '_EMG.txt', ''), '_EMG_means.txt');
        mean_file_path = fullfile(cur_path, mean_data_filename);
        fID = fopen(mean_file_path, 'w');
        
        %% AVERAGE OVER REVOLUTIONS (might be televised - check local listings)
        means = struct();
        % Iterate over variables
        %         try
        for var_no = 2:num_vars+1 % skip frame #
            var_name = var_names{var_no}; % get current variable name
            axis_neg_label = axis_neg{var_no-1}; % indices are offset by one (because Frame # has no label? I dunno - don't ask questions)
            axis_pos_label = axis_pos{var_no-1}; % see above
            cur_low_limit = low_limit(var_no-1); % get min label
            cur_high_limit = high_limit(var_no-1); % get max label
            cur_units = units{var_no-1}; % get units
            orig_var_name = var_name; %?
            deez_revs = revs_over_360.(var_name); % get allz teh revs
            rev_means = transpose(mean(transpose(deez_revs))); % compute the mean (all data is interpolated over the same angle grid, so we can do this and the world will likely not end*)
            %             % Filter means, using 4th order butterworth bandpass filter w/zero phase offset
            %             BP_mean = bandPassFilterData(raw_means,bandpass_low, bandpass_high, time_step, 0, output_folder);
            %             % rectify
            %             rect_mean = abs(BP_mean);
            %             % low-pass filter
            %             filt_mean = lowpassFilterData(rect_mean, lowpass_cutoff, time_step, 0, output_folder);
            %             % moving-window-average
            %             mavg_mean = movmean(filt_mean, moving_window_size);
            %             % save over original
            means.(var_name) = rev_means;
            rev_stds = transpose(std(transpose(deez_revs)));
            stds.(var_name) = rev_stds;
            %             % plot the steps
            %             fig = figure;
            %             x_data = getTime(rev_means, time_step);
            %             plot(x_data, rev_means-mean(rev_means));
            %             hold on;
            % %             plot(x_data, BP_mean);
            % %             plot(x_data, rect_mean);
            % %             plot(x_data, filt_mean);
            % %             plot(x_data, mavg_mean);
            %             [filename,~,~] = fileparts(EMG_file.name);
            %             title_string = strrep(strcat(filename, ' ', var_name, ' EMG Processing Steps'), '_', ' ');
            %             title(title_string);
            %             xlabel('Time (S)');
            %             ylabel('Signal Level (V)');
            % %             raw_legend = 'Raw';
            % %             BP_legend = strcat('Bandpass Filtered @ ', num2str(bandpass_low), '-', num2str(bandpass_high), ' Hz');
            % %             rect_legend = 'Rectified';
            % %             filt_legend = strcat('Lowpass Filtered @ ', num2str(lowpass_cutoff), ' Hz');
            % %             mavg_legend = strcat('Moving-Average @ ', num2str(moving_avg_window), 'ms Window');
            % %             legend(raw_legend, BP_legend, rect_legend, filt_legend, mavg_legend);
            %             fig_file = [output_folder, '\', title_string];
            %             print(fig_file, '-dpng');
            %             savefig(fig_file);
            %             close(fig);
            % write mean value to "mean_file_path" here
            fprintf(fID, '%s\t', var_name);
            fprintf(fID, '%8.2f\t', means.(var_name));
            fprintf(fID, '\r\n');
            
            %             % Plot frequency spectrums
            %             % Raw PSD
            %             signal = rev_means;
            %             N = length(signal);
            %             freqs = 0:sampling_rate/N:f_nyquist;
            %             file_name = strsplit(trc_file.name, '1-');
            %             fig_title = strrep([file_name{1}, ' ', var_name], '_', ' ');
            %             fig = figure;
            %             hold on;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             N_2 = ceil(N/2);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             title(fig_title);
            %             xlabel('Frequency (Hz)');
            %             ylabel('Power (Watts)');
            %             % BP PSD
            %             signal = BP_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             % rect_PSD
            %             signal = rect_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             % filt PSD
            %             signal = filt_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             % mavg PSD
            %             signal = mavg_mean;
            %             % compute magnitude spectrum
            %             x_fft = fft(signal - mean(signal));
            % %             plot(freqs, abs(x_fft(1:N/2+1)));
            %             % compute power spectrum
            %             P_xx = x_fft.*conj(x_fft);
            %             plot(freqs, abs(P_xx(1:N_2)));
            %             legend(raw_legend, BP_legend, rect_legend, filt_legend, mavg_legend);
            %             savePlot(fig, output_folder, fig_title);
            %             close;
        end
        %         catch ME %
        %             error_string = ['Error averaging over revs for EMG file "', EMG_file.name, '": ', ME.message];
        %             disp(error_string);
        %             continue; % skip this folder, go to next one
        %         end
        
        x_loc = 300;
        y_loc = 300;
        width = 1000;
        height = 500;
        % Plotting
        %         try
        for var_no = 2:num_vars+1 % skip frame #
            axis_neg_label = axis_neg{var_no-1}; % indices are offset by one (because Frame # has no label? I dunno - don't ask questions)
            axis_pos_label = axis_pos{var_no-1}; % see above
            var_name = var_names{var_no}; % get current variable name
            side = var_name(1);
            file_name = strsplit(trc_file.name, '1-');
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % need to filter for stds as well
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            cur_mean = means.(var_name); %?
            cur_stds = stds.(var_name);
            if (or(plot_level == 1, plot_level == 3))
                % plot band of stds (ew)
                fig = figure('position', [x_loc y_loc width height]);
                %                 stds = std(cur_mean);
                mean_plus_std = cur_mean + cur_stds;
                mean_minus_std = cur_mean - cur_stds;
                mean_plot = plot(angle_interp_grid,cur_mean, 'k'); % first time we plot means is so items in the legend are in the correct order
                hold on;
                % Color in the band between +SD and -SD (from https://stackoverflow.com/questions/6245626/matlab-filling-in-the-area-between-two-sets-of-data-lines-in-one-figure)
                x = angle_interp_grid;
                y1 = mean_minus_std;
                y2 = mean_plus_std;
                X = [x',fliplr(x')];
                Y = [y1',fliplr(y2')];
                fract = 220/255;
                SD_plot = fill(X,Y,[fract,fract,fract]);
                set(SD_plot,'EdgeColor', 'none');
                second_mean_plot = plot(angle_interp_grid,cur_mean, 'k'); % second time we plot means is so it shows up on top of the SD fill
                set(get(get(second_mean_plot,'Annotation'),'LegendInformation'),'IconDisplayStyle','off'); % but we don't want it to show up in the legend
                % Add labels
                xlabel('Crank Angle (deg)');
                ylabel(['Signal Level (', cur_units, ')']);
                fig_title = strrep([file_name{1}, ' ', var_name],'_', ' '); % replace underscores with spaces (they are interpreted as subscripts)
                fig_title = strrep(fig_title, '  ', ' '); % replace double-space with single-space (some headers have spaces, some dont') OK, that didn't work
                title(fig_title);
                if ~isempty(axis_pos_label)
                    % Add positive value label
                    text_box = uicontrol('style', 'text');
                    text_length = length(axis_pos_label);
                    set(gcf, 'units', 'characters');
                    pos = get(gcf,'Position');
                    fig_width = pos(3);
                    text_normalized_length = (text_length+3)/fig_width;
                    set(text_box, 'String', axis_pos_label);
                    set(text_box, 'Units', 'normalized');
                    set(text_box, 'Position', [0.15,0.8,text_normalized_length,0.035]);
                    hold on;
                    % Add negative value label
                    text_box = uicontrol('style', 'text');
                    text_length = length(axis_neg_label);
                    set(gcf, 'units', 'characters');
                    pos = get(gcf,'Position');
                    fig_width = pos(3);
                    text_normalized_length = (text_length+3)/fig_width;
                    set(text_box, 'String', axis_neg_label);
                    set(text_box, 'Units', 'normalized');
                    set(text_box, 'Position', [0.15,0.2,text_normalized_length,0.035]);
                    hold on;
                end
                if ~isnan(cur_low_limit)
                    lims = axis;
                    axis([lims(1), lims(2), cur_low_limit, cur_high_limit]);
                end
                % add baseline EMG mean and SDs
                BL_EMG_idx = var_no - 1; % there is no frame number in the baseline mean/sd table
                BL_EMG_mean = 0;%BL_EMG{BL_EMG_idx,'Mean'};
                BL_EMG_sd = BL_EMG{BL_EMG_idx,'SD'};
                BL_plus_2 = BL_EMG_mean + 2 * BL_EMG_sd;
                BL_plus_3 = BL_EMG_mean + 3 * BL_EMG_sd;
                hline([BL_EMG_mean,BL_plus_2,BL_plus_3], {'-','--',':'}, {'Baseline', 'BL + 2*SD', 'BL + 3*SD'});
                [legend_obj, legend_icons] = legend({'Mean','Standard Deviation'}, 'Location', 'eastoutside');
                patches_in_legend = findobj(legend_icons, 'type', 'patch');
                savePlot(gcf, output_folder, fig_title);
                close;
            end
        end
        
        % Plot L/R pairs
        num_hdrs = length(EMG_headers);
        pairs = struct();
        pair_idx = 1;
        % iterate over headers
        for j = 1:num_hdrs % yeah, I know we should ignore some headers because they're not L/R but work with me, OK?
            cur_hdr = char(EMG_headers(j)); % convert cell array to string
            cur_side = cur_hdr(1); % get the first letter of the EMG header name (it'e either "L" for left side or "R" for right side, e.g. "R Hip FE")
            rest_of_hdr = cur_hdr(2:end);
            if cur_hdr(1) == 'R' % I maybe meant to use "cur_side"?  Only build the pair if this is a "R" variable (because we build the "L" header below)
                % Get its L variable
                L_side_hdr = ['L', rest_of_hdr]; % build name of left side header
                pairs(pair_idx).R_hdr = cur_hdr; % set name of "R" header
                pairs(pair_idx).L_hdr = L_side_hdr; % set name of "L" header
                pairs(pair_idx).R_var_no = j; % set index of the right-side header
                idx_of_pair = find(not(cellfun('isempty', strfind(EMG_headers, L_side_hdr)))); % get the index of the left-side header in the list of EMG headers
                pairs(pair_idx).L_var_no = idx_of_pair; % set index of the left-side header
                pair_idx = pair_idx + 1;
            end
        end
        
        % plot L/R pairs
        if (or(plot_level == 2, plot_level == 3))
            for k = 1:length(pairs)
                cur_R_var = convert_funky_chars(pairs(k).R_hdr);
                cur_L_var = convert_funky_chars(pairs(k).L_hdr);
                cur_R_means = means.(cur_R_var);
                cur_L_means = means.(cur_L_var);
                cur_R_stds = stds.(cur_R_var);
                cur_L_stds = stds.(cur_L_var);
                cur_data_var_no = pairs(k).R_var_no;
                axis_neg_label = axis_neg{cur_data_var_no};
                axis_pos_label = axis_pos{cur_data_var_no};
                cur_low_limit = low_limit(cur_data_var_no);
                cur_high_limit = high_limit(cur_data_var_no);
                % plot band of stds (ew)
                fig = figure;
                R_mean_plus_std = cur_R_means + cur_R_stds;
                R_mean_minus_std = cur_R_means - cur_R_stds;
                L_mean_plus_std = cur_L_means + cur_L_stds;
                L_mean_minus_std = cur_L_means - cur_L_stds;
                
                % plot left side (plot left first so the right side is on top)
                shift_size = int32(length(angle_interp_grid)/2); % need to phase shift left signal by 180 degrees
                shifted_cur_L_means = circshift(cur_L_means, shift_size);
                hold on;
                x = angle_interp_grid;
                y1 = circshift(L_mean_minus_std, shift_size);
                y2 = circshift(L_mean_plus_std, shift_size);
                X = [x',fliplr(x')];
                Y = [y1',fliplr(y2')];
                RGB = [255,204,204];
                left_SD = fill(X,Y,RGB/255);
                set(left_SD,'EdgeColor', 'none');
                left_mean = plot(angle_interp_grid,shifted_cur_L_means, 'r');
                
                % plot right side
                hold on;
                x = angle_interp_grid;
                y1 = R_mean_minus_std;
                y2 = R_mean_plus_std;
                X = [x',fliplr(x')];
                Y = [y1',fliplr(y2')];
                RGB = [204,204,255];
                right_SD = fill(X,Y,RGB/255);
                set(right_SD,'EdgeColor', 'none');
                right_mean = plot(angle_interp_grid, cur_R_means, 'b');
                
                % Add labels
                xlabel('Crank Angle (deg)');
                ylabel(['Signal Level (', cur_units, ')']);
                sideless_var_name = cur_R_var(2:end);
                fig_title = [file_name{1} ' Left and Right' sideless_var_name];
                fig_title = strrep(fig_title, '_', ' ');
                title(fig_title);
                if ~isempty(axis_pos_label)
                    text_box = uicontrol('style', 'text');
                    text_length = length(axis_pos_label);
                    set(gcf, 'units', 'characters');
                    pos = get(gcf,'Position');
                    fig_width = pos(3);
                    text_normalized_length = (text_length+3)/fig_width;
                    set(text_box, 'String', axis_pos_label);
                    set(text_box, 'Units', 'normalized');
                    set(text_box, 'Position', [0.15,0.8,text_normalized_length,0.035]);
                    
                    hold on;
                    text_box = uicontrol('style', 'text');
                    text_length = length(axis_neg_label);
                    set(gcf, 'units', 'characters');
                    pos = get(gcf,'Position');
                    fig_width = pos(3);
                    text_normalized_length = (text_length+3)/fig_width;
                    set(text_box, 'String', axis_neg_label);
                    set(text_box, 'Units', 'normalized');
                    set(text_box, 'Position', [0.15,0.2,text_normalized_length,0.035]);
                    hold on;
                end
                
                % set limits
                if ~isnan(cur_low_limit)
                    lims = axis;
                    axis([lims(1), lims(2), cur_low_limit, cur_high_limit]);
                end
                legend([right_mean, right_SD, left_mean, left_SD], 'Right Mean', 'Right SD','Left Mean', 'Left SD');
                savePlot(gcf, fullfile(output_folder, '\Both Sides'), fig_title);
                close;
            end
        end
        %         catch ME %
        %             error_string = ['Error plotting EMG file "', EMG_file.name, '": ', ME.message];
        %             disp(error_string);
        %             continue; % skip this folder, go to next one
        %         end
        
    end
end
fclose('all');