function [ filtered_data ] = lowpassFilterData( data, lowpass_cutoff ,time_step, plot_on, figure_path)
%filterData Applies 4-th order zero-phase offset lowpass Butterworth filter
%   lowpass_cutoff in Hz
%   time_step in sec
%   computes normalized cutoff freq (w), uses MATLAB functions butter and
%   filtfilt

%   e.g. data = filterData(crank_angle_from_force, 5, 0.01, 0, 'C:\Users\jfalesi\Dropbox\FES Cycling\Code\Jamie''s Code');

    sampling_rate = 1 / time_step;
    nyquist_freq = sampling_rate / 2;
    w = lowpass_cutoff/nyquist_freq;    
    
    [b,a] = butter(2, w); % compute 2nd order low-pass Butterworth filter coefficients
    filtered_data = filtfilt(b,a,data); % apply 4th-order zero phase offset filter

    if plot_on
        title_string = 'Raw and Lowpass-Filtered Data';
        figure;
        plot(data,'.', 'color', 'y');
        hold on;
        plot(filtered_data, 'color', 'b');
        title(title_string);
        legend('Raw Data', 'Filtered Data (4th order Butterworth, zero phase offset)');
        if exist('figure_path', 'var')
            fig_file = [figure_path, '\', title_string];
            print(fig_file, '-dpng');
            savefig(fig_file);
        end 
        close;
    end
    return
end
