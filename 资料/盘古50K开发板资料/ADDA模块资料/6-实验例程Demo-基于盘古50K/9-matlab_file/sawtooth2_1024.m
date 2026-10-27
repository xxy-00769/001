clc;close all;clear all;

rom_depth   = 2^10; 
rom_widths  = 8;
N = 0 : (rom_depth-1) ;
sawtoothx2 = sawtooth(2*pi*N/rom_depth) ;
square_wave = fopen('D:\sawtooth2_1024.dat','w') ;
fprintf(square_wave,'%X\n',round((2^(rom_widths - 1)-1)*sawtoothx2+2^((rom_widths - 1)))); 
fclose(square_wave);