function [ time ] = getTime( data, time_step )
%getTime Summary of this function goes here
%   Detailed explanation goes here
    time = 0:time_step:(length(data)-1)*time_step; %linspace_size(0, length(data), time_step);
    time = time';
end

