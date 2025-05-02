function output_string = convert_funky_chars(input_string)
    % replace "#" with "Num" in "Frame#"
    output_string = strrep(input_string,'#','Num');
    % replace spaces with underscores
    output_string = strrep(output_string, ' ', '_');
    % replace dots too
    output_string = strrep(output_string, '.', '_');
end
