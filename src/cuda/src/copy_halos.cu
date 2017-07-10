/*                             copy_halos.cu
                              --------------------
*/

/* Date:   01-03-2017
   Author: Omer Anjum
   Description:
   Copying halos between host and device. First packing halos to an array before copying to memories either way.
Comments: 
Date: March 17, 2017
Omer Anjum
Very first version of code written. 
*/
#include <stdio.h>
#include <cuComplex.h>
#include "cuda.h"
#include <assert.h>
#include "copyhalos.cuh"

#define grid_rows(j,i,k) grid[(k)*nx*ny+(i)*ny+(j)]
//#define grid_cols(i,j,k) grid[(k)*nx*ny+(j)*ny+(i)]

cudaError_t checkErr(cudaError_t result) {
  if (result != cudaSuccess) {
    fprintf(stderr, "CUDA Runtime Error: %s %d\n", 
            cudaGetErrorString(result), result);
    assert(result == cudaSuccess);
  }
  return result;
}


void copyouterhalostodevice(float *grid, float *d_grid, float *halo, float *d_halo, int Nx, int Ny, int Nz, int halo_depth)
{	
	int nx, ny, nz;
	nx = Nx;
	ny = Ny;
	nz = Nz;
	printf("Nx = %d, Ny = %d, Nz = %d \n", nx, ny, nz);
	
	//int *lnrho;
	int idx;
	//int halo_rows, halo_columns, halo_front, halo_depth;
	int halo_size, d_lnrho_size;
	//halo_rows = halo_columns = halo_front = halo_depth = 2;
	halo_size = (halo_depth*nx*2 + halo_depth*(ny-halo_depth*2)*2)*(nz-halo_depth*2) + nx*ny*(halo_depth*2);
	d_lnrho_size = nx*ny*nz;

	//int device;
	//cudaGetDevice(&device);
	//printf("Using device %d\n", device);
	//cudaSetDevice(device); //Not yet enabled

	//Ensure that we're using a clean device
	//cudaDeviceReset();
	
	
	printf("halo size = %d, d lnrho size = %d", halo_size, d_lnrho_size);
        //halo = (float*) malloc(sizeof(float)*halo_size);
	//lnrho = (int*) malloc(sizeof(int)*d_lnrho_size);
	/*for (int k=0; k < halo_size; k++) {
		halo[k] = 0;
		//printf("%d ",halo[k]);
	}*/	
	//printf("\nlnrho\n ");
	/*for (int k=0; k < nz; k++) {
			for (int j=0; j < ny; j++) {
				for (int i=0; i < nx; i++) {
					int idx = i + j*nx + k*nx*ny;
					lnrho[idx] = 0;
					printf("%d ", lnrho[idx]);
				}
				printf("\n");
			}
				printf("\n------------\n");
		}*/	
	//checkErr(cudaMalloc ((void **) &d_halo, sizeof(float)*halo_size));
	//checkErr(cudaMalloc ((void **) &d_lnrho, sizeof(int)*d_lnrho_size));	

	//--------------------------------------------
	//	Packing Outer Halos to 1D array 
	//--------------------------------------------
	idx = 0;
	for (int k = 0+halo_depth; k < nz-halo_depth; k++ ){
		for (int j = 0; j < halo_depth; j++){// j is selecting top  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = 0; i < nx; i++){	//i is multiplied by ny to hop from column to column 
				halo[idx] = grid_rows(j,i,k);
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
		for (int j = halo_depth; j < ny-halo_depth; j++){// j is selecting rows.
			//printf("\nprinting lcol in row %d of z plane %d\n",j,k);
			for (int i = 0; i < halo_depth; i++){	//writing left colum halo for jth row 
				halo[idx] = grid_rows(j,i,k);
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			for (int i = nx-halo_depth; i < nx; i++){//writing right colum halo for jth row 
				//printf("\nprinting rcol in row %d of z plane %d\n",j,k);
				halo[idx] = grid_rows(j,i,k);
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
		for (int j = ny-halo_depth; j < ny; j++){// j is selecting bottom  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = 0; i < nx; i++){	//i is multiplied by ny to hop from column to column 
				halo[idx] = grid_rows(j,i,k);
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
		}
	}
	//copying front and back at the end of halo
	for (int k = 0; k < halo_depth; k++){
		for (int j = 0; j < ny; j++){// j is selecting top  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = 0; i < nx; i++){	//i is multiplied by ny to hop from column to column 
				halo[idx] = grid_rows(j,i,k);
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
	}
	for (int k = nz-halo_depth; k < nz; k++){
		for (int j = 0; j < ny; j++){// j is selecting top  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = 0; i < nx; i++){	//i is multiplied by ny to hop from column to column 
				halo[idx] = grid_rows(j,i,k);
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
	}
	printf("\n Packing done now loading halos to GPU\n");
	cudaMemcpy(d_halo, halo, sizeof(float)*halo_size  ,cudaMemcpyHostToDevice);
	fillhalosindevice(d_halo, d_grid, nx, ny, nz, halo_depth);
	return;
}

void copyinternalhalostohost(float *grid, float *d_grid, float *halo, float *d_halo, int Nx, int Ny, int Nz, int halo_depth)
{
	int nx, ny, nz;
	nx = Nx;
	ny = Ny;
	nz = Nz;
	printf("Nx = %d, Ny = %d, Nz = %d \n", nx, ny, nz);
	
	int idx;
	int halo_size;
	halo_size = (halo_depth*nx*2 + halo_depth*(ny-halo_depth*2)*2)*(nz-halo_depth*2) + nx*ny*(halo_depth*2);
	//int d_lnrho_size = nx*ny*nz;

	
	//printf("halo size = %d, d lnrho size = %d", halo_size, d_lnrho_size);
        //halo = (int*) malloc(sizeof(int)*halo_size);
	//lnrho = (int*) malloc(sizeof(int)*d_lnrho_size);
	
	//checkErr(cudaMalloc ((void **) &d_halo, sizeof(int)*halo_size));
	//checkErr(cudaMalloc ((void **) &d_lnrho, sizeof(int)*d_lnrho_size));	
	idx = 0;

	/*for (int k=0; k < halo_size; k++) {
		halo[k] = 0;
		//printf("%d ",halo[k]);
	}	
	printf("\nlnrho\n ");
	for (int k=0; k < nz; k++) {
			for (int j=0; j < ny; j++) {
				for (int i=0; i < nx; i++) {
					int idx = i + j*nx + k*nx*ny;
					lnrho[idx] = idx;
					printf("%d ", lnrho[idx]);
				}
				printf("\n");
			}
				printf("\n------------\n");
		}*/	
	printf("\n loading halos and lnrho to GPU\n");
	//cudaMemcpy(d_halo, halo, sizeof(int)*halo_size  ,cudaMemcpyHostToDevice);
	//cudaMemcpy(d_lnrho, lnrho, sizeof(int)*d_lnrho_size  ,cudaMemcpyHostToDevice); // for testing purpose
	fillhalosinhost(d_halo, d_grid, nx, ny, nz, halo_depth);
	cudaMemcpy(halo, d_halo, sizeof(int)*halo_size  ,cudaMemcpyDeviceToHost);

	//------------------------------------------------------------
	//	Unpacking and copying internal halos to grid in host
	//------------------------------------------------------------
	
	idx = 0;
	for (int k = 0+halo_depth; k < nz-halo_depth; k++ ){
		for (int j = 0; j < halo_depth; j++){// j is selecting top  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = halo_depth; i < nx-halo_depth; i++){	//i is multiplied by ny to hop from column to column 
				grid_rows(j,i,k) = halo[idx];
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
		for (int j = 2*halo_depth; j < ny-2*halo_depth; j++){// j is selecting rows.
			//printf("\nprinting lcol in row %d of z plane %d\n",j,k);
			for (int i = 0; i < halo_depth; i++){	//writing left colum halo for jth row 
				grid_rows(j,i,k) = halo[idx];
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			for (int i = nx-halo_depth; i < nx; i++){//writing right colum halo for jth row 
				//printf("\nprinting rcol in row %d of z plane %d\n",j,k);
				grid_rows(j,i,k) = halo[idx];
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
		for (int j = ny-halo_depth; j < ny; j++){// j is selecting bottom  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = halo_depth; i < nx-halo_depth; i++){	//i is multiplied by ny to hop from column to column 
				grid_rows(j,i,k) = halo[idx];
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
		}
	}

	//copying front and back at the end of halo
	for (int k = 0; k < halo_depth; k++){
		for (int j = halo_depth; j < ny-halo_depth; j++){// j is selecting top  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = halo_depth; i < nx-halo_depth; i++){	//i is multiplied by ny to hop from column to column 
				grid_rows(j,i,k) = halo[idx];
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
	}
	for (int k = nz-halo_depth; k < nz; k++){
		for (int j = halo_depth; j < ny-halo_depth; j++){// j is selecting top  rows.
			//printf("\nprinting row %d of z plane %d\n",j,k);
			for (int i = halo_depth; i < nx-halo_depth; i++){	//i is multiplied by ny to hop from column to column 
				grid_rows(j,i,k) = halo[idx];
				//printf("halo[%d] = %d  ", idx, halo[idx]);
				idx++;
			}
			//printf("\n %%%%%%\n ");
		}
	}
	
	//------------------------------------------------------------
	
	return;
}
