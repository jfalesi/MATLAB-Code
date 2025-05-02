function fig_file = savePlot( fig, figure_path, title_string )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

    title_string = strrep(title_string, '\', '');
    title_string = strrep(title_string, '-', 'n');
    title_string = strrep(title_string, '.', 'p');
    if ~exist(figure_path, 'dir')
        mkdir(figure_path);
    end
    fig_file = [figure_path, '\', title_string];
%     fig_file = ['"', fig_file, '"'];
%     print(fig, fig_file, '-dpng');
    savefig(fig, fig_file);
    print(fig, fig_file, '-dpng');
    return
end

