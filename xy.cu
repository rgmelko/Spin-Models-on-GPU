/*! 
    \file xy.cu
    \brief Functions to generate Hamiltonians for the XY model
*/

#include "hamiltonian.h"
__device__ float HOffBondXXY(const int si, const int bra, const float JJ)
{

    float valH;
    //int S0, S1;
    //int T0, T1;

    valH = JJ*0.5; //contribution from the J part of the Hamiltonian

    return valH;

}

__device__ float HOffBondYXY(const int si, const int bra, const float JJ)
{

    float valH;
    //int S0, S1;
    //int T0, T1;

    valH = JJ*0.5; //contribution from the J part of the Hamiltonian

    return valH;


}

__device__ float HDiagPartXY(const int bra, int lattice_Size, int3* d_Bond, const float JJ)
{

    return 0.f;

}//HdiagPart


__global__ void FillDiagonalsXY(int* d_basis, f_hamiltonian H, int* d_Bond, parameters data)
{

    int row = blockIdx.x*blockDim.x + threadIdx.x;

    H.vals[row] = 0.f;
    H.rows[row] = 2*H.sectordim;
    H.cols[row] = 2*H.sectordim;
    H.set[row] = 0;

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

__global__ void FillSparseXY(int* d_basis_Position, int* d_basis, f_hamiltonian H, int* d_Bond, parameters data, int offset)
{

    int dim = H.sectordim;
    int lattice_Size = data.nsite;
    int ii = (blockDim.x/(2*lattice_Size))*(blockIdx.x + offset) + threadIdx.x/(2*lattice_Size);
    int T0 = threadIdx.x%(2*lattice_Size);

#if __CUDA_ARCH__ < 200
    const int array_size = 512;
#elif __CUDA_ARCH__ >= 200
    const int array_size = 1024;
#else
#error Could not detect GPU architecture
#endif

    __shared__ int3 tempbond[32];
    int count;
    __shared__ int temppos[array_size];
    __shared__ float tempval[array_size];
    //__shared__ uint tempi[array_size];
    unsigned int tempi;
    __shared__ unsigned int tempod[array_size];

    int stride = 4*lattice_Size;
    //int tempcount;
    int site = T0%(lattice_Size);
    count = 0;
    int rowtemp;

    int brasector;

    int start = (bool)(dim%array_size) ? (dim/array_size + 1)*array_size : dim/array_size;

    int s;
    //int si, sj;//sk,sl; //spin operators
    //unsigned int tempi;// tempod; //tempj;
    //cuDoubleComplex tempD;

    __syncthreads();

    bool compare;

    if( ii < dim )
    {
        if (T0 < 2*lattice_Size)
        {
            tempi = d_basis[ii];
            //Putting bond info in shared memory
            (tempbond[site]).x = d_Bond[site];
            (tempbond[site]).y = d_Bond[lattice_Size + site];
            (tempbond[site]).z = d_Bond[2*lattice_Size + site];

            __syncthreads();

            //Horizontal bond ---------------
            s = (tempbond[site]).x;
            tempod[threadIdx.x] = tempi;
            brasector = (tempi & (1 << s)) >> s;
            tempod[threadIdx.x] ^= (1<<s);
            s = (tempbond[site]).y;
            brasector ^= (tempi & (1 << s)) >> s;
            tempod[threadIdx.x] ^= (1<<s);

            compare = (d_basis_Position[tempod[threadIdx.x]] != -1) && brasector;
            compare &= (d_basis_Position[tempod[threadIdx.x]] > ii);
            temppos[threadIdx.x] = (compare) ? d_basis_Position[tempod[threadIdx.x]] : dim;
            tempval[threadIdx.x] = HOffBondXXY(site, tempi, data.J1);

            count += (int)compare;
            rowtemp = (T0/lattice_Size) ? ii : temppos[threadIdx.x];
            rowtemp = (compare) ? rowtemp : 2*dim;

            H.vals[ ii*stride + 4*site + (T0/lattice_Size)+ start ] = tempval[threadIdx.x]; //(T0/lattice_Size) ? tempval[threadIdx.x] : cuConj(tempval[threadIdx.x]);
            H.cols[ ii*stride + 4*site + (T0/lattice_Size) + start ] = (T0/lattice_Size) ? temppos[threadIdx.x] : ii;
            H.rows[ ii*stride + 4*site + (T0/lattice_Size) + start ] = rowtemp;

            H.set[ ii*stride + 4*site + (T0/lattice_Size) + start ] = (int)compare;

            //Vertical bond -----------------
            s = (tempbond[site]).x;
            tempod[threadIdx.x] = tempi;
            brasector = (tempi & (1 << s)) >> s;
            tempod[threadIdx.x] ^= (1<<s);
            s = (tempbond[site]).z;
            brasector ^= (tempi & (1 << s)) >> s;
            tempod[threadIdx.x] ^= (1<<s);

            compare = (d_basis_Position[tempod[threadIdx.x]] != -1) && brasector;
            compare &= (d_basis_Position[tempod[threadIdx.x]] > ii);
            temppos[threadIdx.x] =  (compare) ? d_basis_Position[tempod[threadIdx.x]] : dim;
            tempval[threadIdx.x] = HOffBondYXY(site,tempi, data.J1);

            count += (int)compare;
            rowtemp = (T0/lattice_Size) ? ii : temppos[threadIdx.x];
            rowtemp = (compare) ? rowtemp : 2*dim;

            H.vals[ ii*stride + 4*site + 2 + (T0/lattice_Size) + start ] =  tempval[threadIdx.x]; // (T0/lattice_Size) ? tempval[threadIdx.x] : cuConj(tempval[threadIdx.x]);
            H.cols[ ii*stride + 4*site + 2 + (T0/lattice_Size) + start ] = (T0/lattice_Size) ? temppos[threadIdx.x] : ii;
            H.rows[ ii*stride + 4*site + 2 + (T0/lattice_Size) + start ] = rowtemp;

            H.set[ ii*stride + 4*site + 2 + (T0/lattice_Size) + start ] = (int)compare;
        }
    }//end of ii
}//end of FillSparse
