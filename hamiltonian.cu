#include"hamiltonian.h"
/* NOTE: this function uses FORTRAN style matrices, where the values and positions are stored in a ONE dimensional array! Don't forget this! */


/*int main()
{


    int** Bond;

    int how_many = 30;
    Bond = (int**)malloc(how_many*sizeof(int*));
    d_hamiltonian* hamil_lancz = (d_hamiltonian*)malloc(how_many*sizeof(d_hamiltonian));
    int* nsite = (int*)malloc(how_many*sizeof(int));
    int* Sz = (int*)malloc(how_many*sizeof(int));
    float* JJ = (float*)malloc(how_many*sizeof(float));
    int* model_type = (int*)malloc(how_many*sizeof(int));

    for(int i = 0; i < how_many; i++)
    {

        nsite[i] = 16;
        Bond[i] = (int*)malloc(3*nsite[i]*sizeof(int));
        Fill_Bonds_16B(Bond[i]);


        Sz[i] = 0;
        JJ[i] = 1.f;
        model_type[i] = 0;
    }


    int dim;

    int* num_Elem = ConstructSparseMatrix(how_many, model_type, nsite, Bond, hamil_lancz, JJ, Sz );

    return 0;
}*/

__device__ uint bfi(uint x, uint y, uint bit, uint numBits) {
    uint ret;
#if __CUDA_ARCH__ >= 200
      asm("bfi.b32 %0, %1, %2, %3, %4;" :
        "=r"(ret) : "r"(y), "r"(x), "r"(bit), "r"(numBits));
#else
        uint mask = ((1<< numBits) - 1)<< bit;
          ret = x & ~mask;
            ret |= mask & (y<< bit);
#endif
              return ret;
};

__host__ __device__ int idx(int i, int j, int lda)
{

    return (j + (i*lda));
}


/* Function GetBasis - fills two arrays with information about the basis
Inputs: dim - the initial dimension of the Hamiltonian
lattice_Size - the number of sites
Sz - the value of the Sz operator
basis_Position[] - an empty array that records the positions of the basis
basis - an empty array that records the basis
Outputs: basis_Position - a full array now
basis[] - a full array now

*/
__host__ int GetBasis(int dim, int lattice_Size, int Sz, int basis_Position[], int basis[])
{
    unsigned int temp = 0;
    int realdim = 0;

    for (unsigned int i1=0; i1<dim; i1++)
    {
        temp = 0;
        basis_Position[i1] = -1;
        for (int sp =0; sp<lattice_Size; sp++)
        {
            temp += (i1>>sp)&1;
        } //unpack bra
        //if (temp==(lattice_Size/2+Sz) ){
        basis[realdim] = i1;
        basis_Position[i1] = realdim;
        realdim++;
        //cout<<basis[realdim]<<" "<<basis_Position[i1]<<endl;
        //}
    }

    return realdim;

}

/* Function HOffBondX
Inputs: si - the spin operator in the x direction
bra - the state
JJ - the coupling constant
Outputs: valH - the value of the Hamiltonian

*/

__device__ float HOffBondX(const int si, const int bra, const float JJ)
{

    float valH;
    //int S0, S1;
    //int T0, T1;

    valH = JJ*0.5; //contribution from the J part of the Hamiltonian

    return valH;

}

__device__ float HDiagPart(const int bra, int lattice_Size, int2* d_Bond, const float JJ)
{

    int S0b,S1b ; //spins (bra
    int T0,T1; //site
    //int P0, P1, P2, P3; //sites for plaquette (Q)
    //int s0p, s1p, s2p, s3p;
    float valH = 0.f;

    for (int Ti=0; Ti<lattice_Size; Ti++)
    {
        //***HEISENBERG PART

        T0 = (d_Bond[Ti]).x; //lower left spin
        S0b = (bra>>T0)&1;
        //if (T0 != Ti) cout<<"Square error 3\n";
        T1 = (d_Bond[Ti]).y; //first bond
        S1b = (bra>>T1)&1; //unpack bra
        valH += JJ*(S0b-0.5)*(S1b-0.5);

    }//T0

    //cout<<bra<<" "<<valH<<endl;

    return valH;

}//HdiagPart

/* Function: ConstructSparseMatrix:

Inputs: model_Type - tells this function how many elements there could be, what generating functions to use, etc. Presently only supports Heisenberg
lattice_Size - the number of lattice sites
Bond - the bond values ??
hamil_Values - an empty pointer for a device array containing the values
hamil_PosRow - an empty pointer for a device array containing the locations of each value in a row
hamil_PosCol - an empty pointer to a device array containing the locations of each values in a column

Outputs: hamil_Values - a pointer to a device array containing the values
hamil_PosRow - a pointer to a device array containing the locations of each value in a row
hamil_PosCol - a pointer to a device array containing the locations of each values in a column

*/

__host__ void ConstructSparseMatrix(const int how_many, int* model_Type, int* lattice_Size, int** Bond, d_hamiltonian*& hamil_lancz, float* JJ, float* h, int* Sz, int*& count_array, int device)
{

    cudaSetDevice(device);

    int* num_Elem = (int*)malloc(how_many*sizeof(int));
    f_hamiltonian* d_H = (f_hamiltonian*)malloc(how_many*sizeof(f_hamiltonian));

    int stride[how_many];

    int** basis_Position = (int**)malloc(how_many*sizeof(int*));
    int** basis = (int**)malloc(how_many*sizeof(int*));

    int** d_basis_Position = (int**)malloc(how_many*sizeof(int*));
    int** d_basis = (int**)malloc(how_many*sizeof(int*));

    int** d_Bond = (int**)malloc(how_many*sizeof(int*));

    int padded_dim[how_many];
    int raw_size[how_many];

    dim3* bpg = (dim3*)malloc(how_many*sizeof(dim3));
    dim3* tpb = (dim3*)malloc(how_many*sizeof(dim3));

    cudaStream_t stream[how_many];

    cudaError_t status[how_many];

    int* d_num_Elem;
    cudaMalloc(&d_num_Elem, how_many*sizeof(int));

    for(int i = 0; i<how_many; i++)
    {
        num_Elem[i] = 0;
        stride[i] = 2*lattice_Size[i] + 1;

        d_H[i].fulldim = 2;
        for (int ch=1; ch<lattice_Size[i]; ch++) d_H[i].fulldim *= 2;

        basis_Position[i] = (int*)malloc(d_H[i].fulldim*sizeof(int));
        basis[i] = (int*)malloc(d_H[i].fulldim*sizeof(int));

        d_H[i].sectordim = GetBasis(d_H[i].fulldim, lattice_Size[i], Sz[i], basis_Position[i], basis[i]);

        status[i] = cudaMalloc(&d_basis_Position[i], d_H[i].fulldim*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error allocating "<<i<<"th d_basis_Position array: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMalloc(&d_basis[i], d_H[i].sectordim*sizeof(int));

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error allocating "<<i<<"th d_basis array: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaStreamCreate(&stream[i]);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error creating "<<i<<"th stream: "<<cudaGetErrorString(status[i])<<endl;
        }

        num_Elem[i] = d_H[i].sectordim;
        status[i] = cudaMemcpy(d_num_Elem, num_Elem, how_many*sizeof(int), cudaMemcpyHostToDevice);
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying num_Elem array to device in "<<i<<"th stream: "<<cudaGetErrorString(status[i])<<endl;
        }

    } // can insert more code in here to handle model type later

    for(int i = 0; i<how_many; i++)
    {
        status[i] = cudaMemcpyAsync(d_basis_Position[i], basis_Position[i], d_H[i].fulldim*sizeof(int), cudaMemcpyHostToDevice, stream[i]);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying "<<i<<"th basis_Position: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMemcpyAsync(d_basis[i], basis[i], d_H[i].sectordim*sizeof(int), cudaMemcpyHostToDevice, stream[i]);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying "<<i<<"th basis: "<<cudaGetErrorString(status[i])<<endl;
        }

        padded_dim[i] = (bool)(d_H[i].sectordim%512) ? (d_H[i].sectordim/512 + 1)*512 : d_H[i].sectordim;
        raw_size[i] = padded_dim[i] + (2*lattice_Size[i]*d_H[i].sectordim);
        raw_size[i] = (bool)(raw_size[i]%2048) ? (raw_size[i]/2048 + 1)*2048 : raw_size[i];

        status[i] = cudaMalloc(&d_H[i].rows, raw_size[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error creating "<<i<<"th rows array: "<<cudaGetErrorString(status[i])<<endl;
        }
        status[i] = cudaMalloc(&d_H[i].cols, raw_size[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error creating "<<i<<"th cols array: "<<cudaGetErrorString(status[i])<<endl;
        }
        status[i] = cudaMalloc(&d_H[i].vals, raw_size[i]*sizeof(float));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error creating "<<i<<"th values array: "<<cudaGetErrorString(status[i])<<endl;
        }

        /*status[i] = cudaMemset(d_H[i].rows, d_H[i].sectordim + 1, raw_size[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error setting "<<i<<"th d_H_vals array: "<<cudaGetErrorString(status[i])<<endl;
        }*/
        status[i] = cudaMemset(d_H[i].vals, 0, raw_size[i]*sizeof(float));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error setting "<<i<<"th d_H_vals array: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMalloc(&d_H[i].set, raw_size[i]*sizeof(int));
        status[i] = cudaMemset(d_H[i].set, 0, raw_size[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error setting "<<i<<"th d_H_vals array: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMalloc(&d_Bond[i], 2*lattice_Size[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error creating "<<i<<"th bonds array: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMemcpyAsync(d_Bond[i], Bond[i], 2*lattice_Size[i]*sizeof(int), cudaMemcpyHostToDevice, stream[i]);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying "<<i<<"th bonds array: "<<cudaGetErrorString(status[i])<<endl;
        }

        tpb[i].x = lattice_Size[i];
        do
        {
            tpb[i].x *= 2;
        }
        while(tpb[i].x < 512);

        bpg[i].x = (bool)(2*lattice_Size[i]*d_H[i].sectordim)%tpb[i].x ? (((2*lattice_Size[i]*d_H[i].sectordim)/tpb[i].x) + 1) : (2*lattice_Size[i]*d_H[i].sectordim)/tpb[i].x;

        if (bpg[i].x > (1<<16)){
          bpg[i].y = bpg[i].x/(1<<15);
          bpg[i].x = (1 << 15);
        }

        //cout<<bpg[i].x<<" "<<bpg[i].y<<endl;

    }
    for( int i = 0; i < how_many; i++){

        status[i] = cudaStreamSynchronize(stream[i]);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error synchronizing "<<i<<"th stream: "<<cudaGetErrorString(status[i])<<endl;
        }

        FillDiagonals<<<d_H[i].sectordim/512 + 1, 512, device, stream[i]>>>(d_basis[i], d_H[i].sectordim, d_H[i].rows, d_H[i].cols, d_H[i].vals, d_H[i].set, d_Bond[i], lattice_Size[i], JJ[i]);
    }
    for(int i = 0; i < how_many; i++){
        status[i] = cudaStreamSynchronize(stream[i]);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error synchronizing "<<i<<"th stream: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaPeekAtLastError();
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error in "<<i<<"th stream before FillSparse: "<<cudaGetErrorString(status[i])<<endl;
        }


        FillSparse<<<bpg[i].x, tpb[i].x, device, stream[i]>>>(d_basis_Position[i], d_basis[i], d_H[i].sectordim, d_H[i].rows, d_H[i].cols, d_H[i].vals, d_H[i].set, d_Bond[i], lattice_Size[i], JJ[i], h[i], d_num_Elem, i);

        status[i] = cudaPeekAtLastError();
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error in "<<i<<"th stream after FillSparse: "<<cudaGetErrorString(status[i])<<endl;
        }

    }

    for(int i = 0; i < how_many; i++)
    {
        thrust::device_ptr<int> red_ptr(d_H[i].set);
        num_Elem[i] = thrust::reduce(red_ptr, red_ptr + raw_size[i]);
    }
    /*hamstruct* d_H_sort;
    status2 = cudaMalloc(&d_H_sort, *vdim*stride*sizeof(hamstruct));

    if (status2 != CUDA_SUCCESS){
    	std::cout<<"Allocating d_H_sort failed! Error: ";
    	std::cout<<cudaGetErrorString( status1 )<<std::endl;
    	return 1;
    }*/

        /*int iter = 1;
        uint* num_blocks = (uint*)malloc(how_many*sizeof(uint));
	for (int i = 0; i < how_many; i++){
                if (raw_size[i] > 1024) num_blocks[i] = raw_size[i]/1024;
                else num_blocks[i] = raw_size[i];
		cudaStreamSynchronize(stream[i]);		
		ScanBlocks<<<num_blocks[i], 1024, device, stream[i]>>>(d_num_Elem, d_H[i].set, i);
                cout<<iter<<" "<<num_blocks[i]<<" "<<raw_size[i]<<endl;
                
	}

        bool all_done = false;
        bool* done_flag = (bool*)malloc(how_many*sizeof(bool));

        while( !all_done )
        {
            all_done = true;
            for( int i = 0; i < how_many; i++)
            {
                if( !done_flag[i])
                {
                    //done_flag[i] = num_blocks[i] % 1024 > 0;
                    if (num_blocks[i] < 1024)
                    {
                        //num_blocks[i] = 1;
                        done_flag[i] = true;
                        int bound = num_blocks[i];
                        if (num_blocks[i] > 1)
                        {
                          num_blocks[i]--;
                          num_blocks[i] |= num_blocks[i] >> 1;
                          num_blocks[i] |= num_blocks[i] >> 2;
                          num_blocks[i] |= num_blocks[i] >> 4;
                          num_blocks[i] |= num_blocks[i] >> 8;
                          num_blocks[i] |= num_blocks[i] >> 16;
                          num_blocks[i]++;
                        }
                        cout<<bound<<" "<<num_blocks[i]<<endl;
                        ScanBlocksFinal<<< 1, num_blocks[i], device, stream[i] >>>(d_num_Elem, d_H[i].set, i, bound);
                    }
                    if (num_blocks[i] == 1)
                    {
                        done_flag[i] = true;
                        ScanBlocks<<< num_blocks[i], 1024, device, stream[i] >>>(d_num_Elem, d_H[i].set, i);
                        cout<<iter<<" "<<num_blocks[i]<<" "<<raw_size[i]<<endl;
                    } 


                    else
                    {
                      num_blocks[i] /= 1024;
                    
                      iter++;
                      cout<<iter<<" "<<num_blocks[i]<<" "<<raw_size[i]<<endl;

                      ScanBlocks<<< num_blocks[i], 1024, device, stream[i] >>>(d_num_Elem, d_H[i].set, i);
                    }
                }
                all_done = (all_done && done_flag[i]);
            }
        }*/
    /*int** scan_holder = (int**)malloc(2*how_many*sizeof(int));
    
        cout<<raw_size[0]<<endl;
  
    
    for(int i = 0; i < how_many; i++)
    {
        cudaMalloc(&scan_holder[i], raw_size[i]*sizeof(int)/1024);
        BallotScanBlock<<< raw_size[i]/1024, 1024, device, stream[i]>>>(d_H[i].set, scan_holder[i], NULL, i, false);
    }

    int* h_scan = (int*)malloc(raw_size[0]*sizeof(int)/1024);
    cudaMemcpy(h_scan, scan_holder[0], raw_size[0]*sizeof(int)/1024, cudaMemcpyDeviceToHost);

            ofstream fout;
            fout.open("hamiltonian.log");
            for(int j = 0; j < raw_size[0]/1024; j++)
            {
                fout<<h_scan[j]<<std::endl;

            }
            fout.close();
    for(int i = 0; i < how_many; i++)
    {
        cudaMalloc(&scan_holder[i + how_many], (raw_size[i]/(1024*1024))%1024 ? (raw_size[i]*sizeof(int)/(1024*1024)) : ((raw_size[i]/(1024*1024*1024)) + 1)*1024*sizeof(int) );
        cudaMemset(scan_holder[i + how_many], 0,  (raw_size[i]/(1024*1024))%1024 ? (raw_size[i]*sizeof(int)/(1024*1024)) : ((raw_size[i]/(1024*1024*1024)) + 1)*1024*sizeof(int)); 
        BallotScanBlock<<< raw_size[i]/(1024*1024), 1024, device, stream[i]>>>(scan_holder[i], scan_holder[i + how_many], NULL, i, false);
    }

    cudaMemcpy(h_scan, scan_holder[how_many], raw_size[0]*sizeof(int)/(1024*1024), cudaMemcpyDeviceToHost);
            ofstream fout;
            fout.open("hamiltonian.log");
            for(int j = 0; j < raw_size[0]/(1024*1024); j++)
            {
                fout<<h_scan[j]<<std::endl;

            }
            fout.close();
    for(int i = 0; i < how_many; i++)
    {
        BallotScanBlock<<< 1, 1024, device, stream[i]>>>(scan_holder[i + how_many], d_H[i].set, d_num_Elem, i, true);
    }        
    cout<<endl;
    cudaThreadSynchronize();

    for(int i = 0; i < how_many; i++)
    {
        cudaFree(scan_holder[i]);
	cudaFree(scan_holder[i + how_many]);
    }
    free(scan_holder);

    //int* num_ptr;
    //cudaGetSymbolAddress((void**)&num_ptr, (const char*)"d_num_Elem");*/

    //cudaMemcpy(num_Elem, d_num_Elem, how_many*sizeof(int), cudaMemcpyDeviceToHost);
    //std::cout<<num_Elem<<std::endl;
    for(int i = 0; i < how_many; i++)
    {

        status[i] = cudaFree(d_basis[i]);
        if ( status[i] != CUDA_SUCCESS)
        {
            cout<<"Error freeing "<<i<<"th basis array: "<<cudaGetErrorString(status[i])<<endl;
        }
        status[i] = cudaFree(d_basis_Position[i]);
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error freeing "<<i<<"th basis_Position array: "<<cudaGetErrorString(status[i])<<endl;
        }
        status[i] = cudaFree(d_Bond[i]); // we don't need these later on
        if (status[i] != CUDA_SUCCESS)
        {

            cout<<"Error freeing "<<i<<"th Bond array: "<<cudaGetErrorString(status[i])<<endl;
        }
        free(basis[i]);
        free(basis_Position[i]);
    }
    //----------------Sorting Hamiltonian--------------------------//


    float** vals_buffer = (float**)malloc(how_many*sizeof(float*));
    int sortnumber[how_many];

    for(int i = 0; i<how_many; i++)
    {

        sortEngine_t engine;
        sortStatus_t sortstatus = sortCreateEngine("sort/sort/src/cubin64/", &engine);

        MgpuSortData sortdata;

        sortnumber[i];

        sortdata.AttachKey((uint*)d_H[i].rows);
        sortdata.AttachVal(0, (uint*)d_H[i].cols);
        sortdata.AttachVal(1, (uint*)d_H[i].vals);

        sortnumber[i] = raw_size[i];

        sortdata.Alloc(engine, sortnumber[i], 2);

        sortdata.firstBit = 0;
        sortdata.endBit = 32; //lattice_Size[i] + 1;

        sortArray(engine, &sortdata);

        //sortReleaseEngine(engine);
        /*thrust::device_ptr<int> sort_key_ptr(d_H_rows);
        thrust::device_ptr<int> sort_val_ptr(d_H_cols);

        thrust::sort_by_key(sort_key_ptr, sort_key_ptr + *vdim*stride, sort_val_ptr);*/
        
        status[i] = cudaMalloc(&hamil_lancz[i].vals, num_Elem[i]*sizeof(double));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error allocating "<<i<<"th lancz values array: "<<cudaGetErrorString(status[i])<<endl;
        }
        status[i] = cudaMalloc(&hamil_lancz[i].rows, num_Elem[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error allocating "<<i<<"th lancz rows array: "<<cudaGetErrorString(status[i])<<endl;
        }
        status[i] = cudaMalloc(&hamil_lancz[i].cols, num_Elem[i]*sizeof(int));
        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error allocating "<<i<<"th lancz cols array: "<<cudaGetErrorString(status[i]);
        }

        cudaMemcpy(hamil_lancz[i].rows, (int*)sortdata.keys[0], num_Elem[i]*sizeof(int), cudaMemcpyDeviceToDevice);

        cudaMemcpy(hamil_lancz[i].cols, (int*)sortdata.values1[0], num_Elem[i]*sizeof(int), cudaMemcpyDeviceToDevice);

        cudaMalloc(&vals_buffer[i], num_Elem[i]*sizeof(float));

        cudaMemcpy(vals_buffer[i], (float*)sortdata.values2[0], num_Elem[i]*sizeof(float), cudaMemcpyDeviceToDevice);
        FullToCOO<<<num_Elem[i]/1024 + 1, 1024>>>(num_Elem[i], vals_buffer[i], hamil_lancz[i].vals, d_H[i].sectordim); // csr and description initializations happen somewhere else

        sortReleaseEngine(engine);

        cudaFree(d_H[i].rows);
        cudaFree(d_H[i].cols);
        cudaFree(d_H[i].vals);
        cudaFree(d_H[i].set);

        hamil_lancz[i].fulldim = d_H[i].fulldim;
        hamil_lancz[i].sectordim = d_H[i].sectordim;

        /*double* h_vals = (double*)malloc(num_Elem[i]*sizeof(double));
        int* h_rows = (int*)malloc(num_Elem[i]*sizeof(int));
        int* h_cols = (int*)malloc(num_Elem[i]*sizeof(int));

        status[i] = cudaMemcpy(h_vals, hamil_lancz[i].vals, num_Elem[i]*sizeof(double), cudaMemcpyDeviceToHost);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying to h_vals: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMemcpy(h_rows, hamil_lancz[i].rows, num_Elem[i]*sizeof(int), cudaMemcpyDeviceToHost);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying to h_rows: "<<cudaGetErrorString(status[i])<<endl;
        }

        status[i] = cudaMemcpy(h_cols, hamil_lancz[i].cols, num_Elem[i]*sizeof(int), cudaMemcpyDeviceToHost);

        if (status[i] != CUDA_SUCCESS)
        {
            cout<<"Error copying to h_cols: "<<cudaGetErrorString(status[i])<<endl;
        }*/


        /*if(i == 0)
        {
            cout<<num_Elem[i]<<endl;
            ofstream fout;
            fout.open("hamiltonian.log");
            for(int j = 0; j < num_Elem[i]; j++)
            {
                fout<<"("<<h_rows[j]<<","<<h_cols[j]<<")";
                fout<<" - "<<h_vals[j]<<std::endl;

            }
            fout.close();
        }*/
        cudaStreamSynchronize(stream[i]);
        cudaFree(vals_buffer[i]);
        free(Bond[i]);
    }
    //cout<<num_Elem[0]<<" "<<d_H[0].sectordim<<endl;
    cudaDeviceSynchronize();
    free(d_basis_Position);
    free(d_Bond);
    free(d_basis);
    free(basis);
    free(basis_Position);
    free(d_H);
    free(bpg);
    free(tpb);
    free(vals_buffer);
    memcpy(count_array, num_Elem, how_many);
    free(num_Elem);
    cudaFree(d_num_Elem);
    //return num_Elem;
}

__global__ void FillDiagonals(int* d_basis, int dim, int* H_rows, int* H_cols, float* H_vals, int* H_set, int* d_Bond, int lattice_Size, float JJ)
{

    int row = blockIdx.x*blockDim.x + threadIdx.x;
    int site = threadIdx.x%(lattice_Size);

    unsigned int tempi;

    __shared__ int2 tempbond[20];
    //int3 tempbond[16];

    if (row < dim)
    {
        tempi = d_basis[row];
        ( tempbond[ site ] ).x = d_Bond[ site ];
        ( tempbond[ site ] ).y = d_Bond[ lattice_Size + site ];

        H_vals[ row ] = HDiagPart(tempi, lattice_Size, tempbond, JJ);
        H_rows[ row ] = row;
        H_cols[ row ] = row;
        H_set[ row ]  = 1;

    }

    else
    {
        H_rows[ row ] = dim + 1;
        H_cols[ row ] = dim + 1;
        H_set[ row ] = 0;
    }

}

/* Function FillSparse: this function takes the empty Hamiltonian arrays and fills them up. Each thread in x handles one ket |i>, and each thread in y handles one site T0
Inputs: d_basis_Position - position information about the basis
d_basis - other basis infos
d_dim - the number of kets
H_sort - an array that will store the Hamiltonian
d_Bond - the bond information
d_lattice_Size - the number of lattice sites
JJ - the coupling parameter

*/

__global__ void FillSparse(int* d_basis_Position, int* d_basis, int dim, int* H_rows, int* H_cols, float* H_vals, int* H_set, int* d_Bond, const int lattice_Size, const float JJ, const float h, int* num_Elem, int index)
{

    int ii = ( blockDim.x / ( 2 * lattice_Size ) ) * blockIdx.x + threadIdx.x / ( 2 * lattice_Size ) + blockIdx.y* gridDim.x * blockDim.x / (2 * lattice_Size);
    int T0 = threadIdx.x % ( 2 * lattice_Size );

//    printf("%d \n", ii);

#if __CUDA_ARCH__ < 200
    const int array_size = 512;
#elif __CUDA_ARCH__ >= 200
    const int array_size = 1024;
#else
#error Could not detect GPU architecture
#endif

    int count;
    __shared__ int temppos[ array_size ];
    __shared__ float tempval[ array_size ];

    int stride = 2 * lattice_Size;
    int site = T0 % ( lattice_Size );
    count = 0;
    int rowtemp;

    //int start = (bool)(dim%array_size) ? (dim/array_size + 1)*array_size : dim/array_size;
    int start = ( bool )( dim % 512 ) ? ( dim / 512 + 1 ) * 512 : dim ; 
    bool compare;

    if( ii < dim )
    {
        if ( T0 < 2 * lattice_Size )
        {
            //----sigma^x term ------------------------------------------

            temppos[ threadIdx.x ] = ( ii ^ ( 1 << site ) );// & ( 1 << site ); //flip the site-th bit of row - applying the sigma_x operator
            compare = ( temppos[ threadIdx.x ] > ii ) && ( temppos[ threadIdx.x ] < dim );
            temppos[ threadIdx.x ] = compare ? temppos[ threadIdx.x ] : dim + 1;
            tempval[ threadIdx.x ] = 0.5 * h;
            
            rowtemp = ( T0 / lattice_Size ) ? ii : temppos[ threadIdx.x ];
            rowtemp = compare ? rowtemp : dim + 1;
            temppos[ threadIdx.x ] = ( T0 / lattice_Size) ? temppos[ threadIdx.x ] : ii;
            temppos[ threadIdx.x ] = compare ? temppos[threadIdx.x] : dim + 1;

            //count = (H_vals[ idx(ii, 2*site + (T0/lattice_Size) + start, stride) ] < 1e-8) ? (int)compare : 0;
            //count = (bool)H_set[ idx(ii, 2*site + (T0/lattice_Size) + start, stride) ] ? 0 : (int)compare; 
            count += ( int )compare;
            //----Putting everything back into GPU main memory-----------

            H_vals[ idx( ii, 2 * site + ( T0 / lattice_Size ) + start, stride ) ] = tempval[ threadIdx.x ]; 
            H_cols[ idx( ii, 2 * site + ( T0 / lattice_Size ) + start, stride ) ] = temppos[ threadIdx.x ];
            H_rows[ idx( ii, 2 * site + ( T0 / lattice_Size ) + start, stride ) ] = rowtemp;
            H_set[ idx( ii, 2 * site + ( T0 / lattice_Size ) + start, stride ) ] = count;
            //atomicExch(&H_set[ idx(ii, 2*site + (T0/lattice_Size) + start, stride) ], 1); 

            //atomicAdd( &num_Elem[ index ], count);
        }
    }//end of ii
}//end of FillSparse


__global__ void BallotScanBlock(const int* dataIn_global, int* dataOut_global, int* countOut_global, int index, bool done_flag) {
 
    uint tid = threadIdx.x;
    uint gid = tid + blockIdx.x*blockDim.x;
    uint lane = (WARP_SIZE - 1) & tid;
    uint warp = tid / WARP_SIZE;
 
    int val = dataIn_global[gid];
 
    uint flag = (val == 1);
 
    // Ballot scan the flags as in the warp scan version.
    uint bits = __ballot(flag);
    uint mask = bfi(0, 0xffffffff, 0, lane);
    uint exc = __popc(mask & bits);
    uint warpTotal = __popc(bits);
 
    // Store each warp total into shared memory.
    __shared__ volatile uint shared[NUM_WARPS];
    if(!lane) shared[warp] = warpTotal;
 
    // Inclusive scan the warp totals.
    __syncthreads();
    if(tid < NUM_WARPS) {
        uint x = shared[tid];
        for(int i = 0; i < LOG_NUM_WARPS; ++i) {
            uint offset = 1<< i;
            if(tid >= offset) x += shared[tid - offset];
            shared[tid] = x;
        }
    }
    __syncthreads();
 
    // Add the exclusive scanned warp totals into exc.
    uint blockTotal = shared[NUM_WARPS - 1];
    exc += shared[warp] - warpTotal;
 
    // Scatter the defined values to shared memory.
    __shared__ volatile float shared2[NUM_THREADS];
    if(flag) shared2[exc] = val;
 
    // Synchronize and write from shared memory to global memory.  
    __syncthreads();
    if(tid < blockTotal) {
        val = shared2[tid];
        //dataOut_global[gid] = val;
    }
 
    if(!tid){
        if (done_flag) countOut_global[index] = blockTotal;
		dataOut_global[blockIdx.x] = blockTotal;
	}
}


/*Function: FullToCOO - takes a full sparse matrix and transforms it into COO format
Inputs - num_Elem - the total number of nonzero elements
H_vals - the Hamiltonian values
H_pos - the Hamiltonian positions
hamil_Values - a 1D array that will store the values for the COO form

*/
__global__ void FullToCOO(int num_Elem, float* H_vals, double* hamil_Values, int dim)
{

    int i = threadIdx.x + blockDim.x * blockIdx.x;

    if (i < num_Elem)
    {

        hamil_Values[ i ] = H_vals[ i ];


    }
}
;

