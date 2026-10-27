clc;close all;clear all;

rom_depth   = 2^10; 
rom_widths  = 8;
N = 0 : (rom_depth-1) ;
squarex = square(2*pi*N/rom_depth) ;
square_wave = fopen('D:\square_1024.dat','w') ;
fprintf(square_wave,'%X\n',round((2^(rom_widths - 1)-1)*squarex+2^((rom_widths - 1)))); 
fclose(square_wave);