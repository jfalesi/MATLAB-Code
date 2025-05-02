function filename = get_filename( file )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
    [~,filename,~] = fileparts(file.name);
return
end

