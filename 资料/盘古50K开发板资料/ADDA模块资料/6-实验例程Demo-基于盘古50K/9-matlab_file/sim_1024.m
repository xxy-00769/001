clc;close all;clear all;

rom_depth   = 2^10; 
rom_widths  = 8;
N = 0 : (rom_depth-1) ;
sinx = sin(2*pi*N/rom_depth) ;
sin_wave = fopen('D:\sin_1024.dat','w') ;
fprintf(sin_wave,'%X\n',round((2^(rom_widths - 1)-1)*sinx+(2^(rom_widths - 1))));
fclose(sin_wave);