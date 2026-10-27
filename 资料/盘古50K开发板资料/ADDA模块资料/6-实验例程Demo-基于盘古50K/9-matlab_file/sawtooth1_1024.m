clc;close all;clear all;

rom_depth   = 2^10; 
rom_widths  = 8;
N = 0 : (rom_depth-1) ;
sawtoothx1 = sawtooth(2*pi*N/rom_depth, 1/2) ;
square_wave = fopen('D:\sawtooth1_1024.dat','w') ;
fprintf(square_wave,'%X\n',round((2^(rom_widths - 1)-1)*sawtoothx1+2^((rom_widths - 1)))); 
fclose(square_wave);
