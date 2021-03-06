/*============================================================================
nbody.cl

OpenCL implementation of vortex particle N-Body problem using brute force.

Copyright(c) 2018-2020 HJA Bird

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files(the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions :

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
============================================================================*/

/* CVTX_CL_WORKGROUP_SIZE controlled with build options from host 		*/
/* CVTX_CL_LOG2_WORKGROUP_SIZE controlled with build options from host */

/*############################################################################
Definitions for the repeated body of kernels
############################################################################*/


"#define SQRT_2_OVER_PI 0.7978845608028654f							\n"
"#define ONE_OVER_SQRT_TWO 0.7071067811865475f						\n"

"#define CVTX_P3D_VEL_START 										\\\n"
"(																	\\\n"
"	__global float3* particle_locs,									\\\n"
"	__global float3* particle_vorts,								\\\n"
"	float    recip_reg_rad,								            \\\n"
"	__global float3* mes_locs,										\\\n"
"	__global float3* results)										\\\n"
"{																	\\\n"
"	float3 rad, num, ret;											\\\n"
"	float cor, den, rho, g, radd;									\\\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* Particle idx, mes_pnt idx and local work item idx */			\\\n"
"	uint pidx, midx, widx, loop_idx;								\\\n"
"	midx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	pidx = widx;													\\\n"
"	rad = mes_locs[midx] - particle_locs[pidx];						\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd * recip_reg_rad;    									\n"

/* Fill in g calc here */

"#define CVTX_P3D_VEL_END 											\\\n"
"	cor = - g;	/*1/4pi term is done by host. */					\\\n"
"	den = pown(radd, 3);											\\\n"
"	num = cross(rad, particle_vorts[pidx]);							\\\n"
"	ret = num * (cor / den);										\\\n"
"	ret = isnormal(ret) && radd != 0.f ? ret : (float3)(0.f, 0.f, 0.f);\\\n"
"	reduction_workspace[widx] = ret;								\\\n"
"	local_workspace_float3_reduce(reduction_workspace);				\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[midx] = reduction_workspace[0] + results[midx];		\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

"#define CVTX_P3D_DVORT_START										\\\n"
"(																	\\\n"
"	__global float3* particle_locs,									\\\n"
"	__global float3* particle_vorts,								\\\n"
"	float    recip_reg_rad,			        						\\\n"
"	__global float3* induced_locs,									\\\n"
"	__global float3* induced_vorts,									\\\n"
"	__global float3* results)										\\\n"
"{																	\\\n"
"	float3 ret, rad, cross_om, t21, t21n, t22;						\\\n"
"	float g, f, radd, rho, recip_rho3, t221, t222, t223;			\\\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* self (inducing particle) index, induced particle index */	\\\n"
"	uint sidx, indidx, widx;										\\\n"
"	indidx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	sidx = widx;													\\\n"
"	rad = induced_locs[indidx] - particle_locs[sidx];				\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd * recip_reg_rad;  									\n"

/* FILL in f & g calc here! */

"#define CVTX_P3D_DVORT_END											\\\n"
"	cross_om = cross(induced_vorts[indidx], particle_vorts[sidx]);	\\\n"
"	t21n = cross_om * g;											\\\n"
"	recip_rho3 = 1.f/(rho * rho * rho);								\\\n"
"	t21 = t21n * recip_rho3;										\\\n"
"	t221 = -1.f / (radd * radd);									\\\n"
"	t222 = 3 * g * recip_rho3 - f;									\\\n"
"	t223 = dot(rad, cross_om);										\\\n"
"	ret = fma(t221 * t222 * t223, rad, t21); /* 1/(4 pi reg_dist^3) is host side */\\\n"
"	ret = isnormal(ret) && radd > 0.f ? ret : (float3)(0.f, 0.f, 0.f);\\\n"
"	reduction_workspace[widx] = ret;								\\\n"
"	local_workspace_float3_reduce(reduction_workspace);				\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[indidx] = reduction_workspace[0] + results[indidx];	\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

"float sphere_volume(float radius){									\n"
"	return 4 * acos((float)-1) * radius * radius * radius / 3.f;    \n"
"}																	\n"

"#define CVTX_P3D_VISC_DVORT_START									\\\n"
"(																	\\\n"
"	__global float3* particle_locs,									\\\n"
"	__global float3* particle_vorts,								\\\n"
"	__global float* particle_vols,									\\\n"
"	__global float3* induced_locs,									\\\n"
"	__global float3* induced_vorts,									\\\n"
"	__global float* induced_vols,									\\\n"
"	__global float3* results,										\\\n"
"	float regularisation_dist,										\\\n"
"	float kinematic_visc)											\\\n"
"{																	\\\n"
"	float3 ret, rad, t211, t212, t21, t2;							\\\n"
"	float radd, rho, t1, eta;										\\\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* self (inducing particle) index, induced particle index */	\\\n"
"	uint sidx, indidx, widx, loop_idx;								\\\n"
"	sidx = get_global_id(0);										\\\n"
"	indidx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	rad = particle_locs[sidx] - induced_locs[indidx];				\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd / regularisation_dist;								\\\n"
"	t1 =  2 * kinematic_visc / pown(regularisation_dist, 2);		\\\n"
"	t211 = particle_vorts[sidx] * induced_vols[indidx];  			\\\n"
"	t212 = -1 * induced_vorts[indidx] * particle_vols[sidx];		\\\n"
"	t21 = t211 + t212;												\n"

/* ETA FUNCTION function!  here */

"#define CVTX_P3D_VISC_DVORT_END									\\\n"
"	t2 = t21 * eta;													\\\n"
"	ret = t2 * t1;													\\\n"
"	ret = isnormal(ret) && radd != 0.f ? ret : (float3)(0.f, 0.f, 0.f);\\\n"
"	reduction_workspace[widx] = convert_float3(ret);				\\\n"
"	local_workspace_float3_reduce(reduction_workspace);				\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[indidx] = reduction_workspace[0] + results[indidx];	\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

"#define CVTX_P3D_VORT_START 										\\\n"
"(																	\\\n"
"	__global float3* particle_locs,									\\\n"
"	__global float3* particle_vorts,								\\\n"
"	float    recip_reg_rad,								            \\\n"
"	__global float3* mes_locs,										\\\n"
"	__global float3* results)										\\\n"
"{																	\\\n"
"	float3 rad, ret;												\\\n"
"	float radd, rho, zeta;											\\\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* Particle idx, mes_pnt idx and local work item idx */			\\\n"
"	uint pidx, midx, widx, loop_idx;								\\\n"
"	midx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	pidx = widx;													\\\n"
"	rad = mes_locs[midx] - particle_locs[pidx];						\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd * recip_reg_rad;    									\n"

/* Fill in zeta calc here */

"#define CVTX_P3D_VORT_END 											\\\n"
"	/* 1/(4pi sigma^3) term is done by host. */						\\\n"
"	ret = zeta * particle_vorts[pidx];								\\\n"
"	ret = isnormal(ret) && radd != 0.f ? ret : (float3)(0.f, 0.f, 0.f);\\\n"
"	reduction_workspace[widx] = ret;								\\\n"
"	local_workspace_float3_reduce(reduction_workspace);				\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[midx] = reduction_workspace[0] + results[midx];		\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

/* 	Summation of local array of float3 of length CVTX_CL_WORKGROUP_SIZE
	with result left in array[0]	*/
"inline void local_workspace_float3_reduce(									\n"
"	__local float3* reduction_workspace)									\n"
"{																			\n"
"	uint loop_idx = 2;														\n"
"	uint widx = get_local_id(0);											\n"
"	for(; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 								\n"
"		loop_idx *= 2)														\n"
"	{																		\n"
"		barrier(CLK_LOCAL_MEM_FENCE);										\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){						\n"
"			reduction_workspace[widx] = reduction_workspace[widx] 			\n"
"				+  reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\n"
"		}																	\n"
"	}																		\n"
"	return;																	\n"
"}																			\n"

/* 2D Vortex particle induced velocity */

"#define CVTX_P2D_VEL_START 										\\\n"
"(																	\\\n"
"	__global float2* particle_locs,									\\\n"
"	__global float* particle_vorts,									\\\n"
"	float    recip_reg_rad,								            \\\n"
"	__global float2* mes_locs,										\\\n"
"	__global float2* results)										\\\n"
"{																	\\\n"
"	float2 rad, ret;												\\\n"
"	float cor, den, rho, g, radd;									\\\n"
"	__local float2 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* Particle idx, mes_pnt idx and local work item idx */			\\\n"
"	uint pidx, midx, widx, loop_idx;								\\\n"
"	midx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	pidx = widx;													\\\n"
"	rad = mes_locs[midx] - particle_locs[pidx];						\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd * recip_reg_rad;    									\n"

/* Fill in g calc here */

"#define CVTX_P2D_VEL_END 											\\\n"
"	cor = g;	/*1/2pi term is done by host. */					\\\n"
"	den = pown(radd, 2);											\\\n"
"	ret.x = rad.y * (cor * particle_vorts[pidx] / den);				\\\n"
"	ret.y = -rad.x * (cor * particle_vorts[pidx] / den);			\\\n"
"	ret = isnormal(ret) && radd != 0.f ? ret : (float2)(0.f, 0.f);	\\\n"
"	reduction_workspace[widx] = ret;								\\\n"
"	local_workspace_float2_reduce(reduction_workspace);				\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[midx] = reduction_workspace[0] + results[midx];		\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"	

/*	P2D vel for small numbers of measurement points */
"#define CVTX_P2D_SMALLMES_VEL_START 								\\\n"
"(																	\\\n"
"	__global float2* particle_locs,									\\\n"
"	__global float* particle_vorts,									\\\n"
"	float    recip_reg_rad,								            \\\n"
"	__global float2* mes_locs,										\\\n"
"	__global float2* results,										\\\n"
"	unsigned int num_mes)											\\\n"
"{																	\\\n"
"	float2 rad, ret;												\\\n"
"	float cor, den, rho, g, radd;									\\\n"
"	__local float2 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* Particle idx, mes_pnt idx and local work item idx */			\\\n"
"	uint pidx, midx, widx, loop_idx;								\\\n"
"	midx = get_global_id(1);										\\\n"
"	widx = get_global_id(0);										\\\n"
"	pidx = widx + CVTX_CL_WORKGROUP_SIZE * (midx / num_mes);		\\\n"
"	rad = mes_locs[midx] - particle_locs[pidx];						\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd * recip_reg_rad;    									\n"

"#define CVTX_P2D_SMALLMES_VEL_END 									\\\n"
"	cor = g;	/*1/2pi term is done by host. */					\\\n"
"	den = pown(radd, 2);											\\\n"
"	ret.x = rad.y * (cor * particle_vorts[pidx] / den);				\\\n"
"	ret.y = -rad.x * (cor * particle_vorts[pidx] / den);			\\\n"
"	ret = isnormal(ret) && radd != 0.f ? ret : (float2)(0.f, 0.f);	\\\n"
"	reduction_workspace[widx] = ret;								\\\n"
"	local_workspace_float2_reduce(reduction_workspace);				\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[midx] = reduction_workspace[0];						\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"	

"#define CVTX_P2D_VISC_DVORT_START									\\\n"
"(																	\\\n"
"	__global float2* particle_locs,									\\\n"
"	__global float* particle_vorts,									\\\n"
"	__global float* particle_areas,									\\\n"
"	__global float2* induced_locs,									\\\n"
"	__global float* induced_vorts,									\\\n"
"	__global float* induced_areas,									\\\n"
"	__global float* results,										\\\n"
"	float regularisation_dist,										\\\n"
"	float kinematic_visc)											\\\n"
"{																	\\\n"
"	float2 rad;														\\\n"
"	float ret, radd, rho, t1, t2, t21, t211, t212, eta;				\\\n"
"	__local float reduction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	__local float correction_workspace[CVTX_CL_WORKGROUP_SIZE];		\\\n"
"	/* self (inducing particle) index, induced particle index */	\\\n"
"	uint sidx, indidx, widx, loop_idx;								\\\n"
"	sidx = get_global_id(0);										\\\n"
"	indidx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	rad = particle_locs[sidx] - induced_locs[indidx];				\\\n"
"	radd = length(rad);												\\\n"
"	rho = radd / regularisation_dist;								\\\n"
"	t1 =  2 * kinematic_visc / pown(regularisation_dist, 2);		\\\n"
"	t211 = particle_vorts[sidx] * induced_areas[indidx];  			\\\n"
"	t212 = -1 * induced_vorts[indidx] * particle_areas[sidx];		\\\n"
"	t21 = t211 + t212;												\n"

/* ETA FUNCTION function!  here */

"#define CVTX_P2D_VISC_DVORT_END									\\\n"
"	t2 = t21 * eta;													\\\n"
"	ret = t2 * t1;													\\\n"
"	ret = isnormal(ret) && radd != 0 ? ret : 0.f;					\\\n"
"	reduction_workspace[widx] = ret;								\\\n"
"	local_workspace_float_reduce_corrected(							\\\n"
"		reduction_workspace, correction_workspace);					\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[indidx] = reduction_workspace[0] + 					\\\n"
"			correction_workspace[0] + results[indidx];				\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

/* 	Summation of local array of float2 of length CVTX_CL_WORKGROUP_SIZE
	with result left in array[0]	*/
"inline void local_workspace_float2_reduce(									\n"
"	__local float2* reduction_workspace)									\n"
"{																			\n"
"	uint loop_idx = 2;														\n"
"	uint widx = get_local_id(0);											\n"
"	for(; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 								\n"
"		loop_idx *= 2)														\n"
"	{																		\n"
"		barrier(CLK_LOCAL_MEM_FENCE);										\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){						\n"
"			reduction_workspace[widx] = reduction_workspace[widx] 			\n"
"				+  reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\n"
"		}																	\n"
"	}																		\n"
"	return;																	\n"
"}																			\n"

/* 	Summation of local array of float of length CVTX_CL_WORKGROUP_SIZE
	with result left in array[0]	*/
"inline void local_workspace_float_reduce(									\n"
"	__local float* reduction_workspace)										\n"
"{																			\n"
"	uint loop_idx = 2;														\n"
"	uint widx = get_local_id(0);											\n"
"	for(; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 								\n"
"		loop_idx *= 2)														\n"
"	{																		\n"
"		barrier(CLK_LOCAL_MEM_FENCE);										\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){						\n"
"			reduction_workspace[widx] = reduction_workspace[widx] 			\n"
"				+  reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\n"
"		}																	\n"
"	}																		\n"
"	return;																	\n"
"}																			\n"

/*  Summation of local array of float of length CVTX_CL_WORKGROUP_SIZE with 
	result left in array[0] and correction in correction[0].				
	overwrites correction away (ie. don't need to zero it first.			*/
"inline void local_workspace_float_reduce_corrected(						\n"
"	__local float* reduction_workspace, 									\n"
"	__local float* correction_workspace)									\n"
"{																			\n"
"	uint loop_idx = 2;														\n"
"	uint widx = get_local_id(0);											\n"
/*	Summation variables sa and sb, and lower bit corrections ca and cb.		*/
"	float sa, sb, ca, cb, t;												\n"
"	correction_workspace[widx] = 0.f;										\n"
"	for(; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 								\n"
"		loop_idx *= 2)														\n"
"	{																		\n"
"		barrier(CLK_LOCAL_MEM_FENCE);										\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){						\n"
"			sa = reduction_workspace[widx];									\n"
"			sb = reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\n"
"			ca = correction_workspace[widx];								\n"
"			cb = correction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\n"
"			t = sa + sb;													\n"
"			if( fabs(sa) >= fabs(sb)){										\n"
"				ca += (sa - t) + sb;										\n"
"			} else {														\n"
"				ca += (sb - t) + sa;										\n"
"			}																\n"
"			reduction_workspace[widx] = t;									\n"
"			correction_workspace[widx] = ca + cb;							\n"
"		}																	\n"
"	}																		\n"
"	return;																	\n"
"}																			\n"

/* 	###########################################################
	3D Velocity calculation kernels here:
	name cvtx_nb_P3D_vel_XXXXX
	###########################################################	*/

"__kernel void cvtx_nb_P3D_vel_singular\n"
"	CVTX_P3D_VEL_START														\n"
"	g = 1.f;																\n"
"	CVTX_P3D_VEL_END														\n"


"__kernel void cvtx_nb_P3D_vel_winckelmans									\n"
"	CVTX_P3D_VEL_START														\n"
"	g = (rho * rho + 2.5f) * rho * rho * rho * rsqrt(pown(rho * rho + 1, 5));\n"
"	CVTX_P3D_VEL_END														\n"


"__kernel void cvtx_nb_P3D_vel_planetary									\n"
"	CVTX_P3D_VEL_START														\n"
"	g = rho < 1.f ? rho * rho * rho : 1.f;									\n"
"	CVTX_P3D_VEL_END														\n"


"__kernel void cvtx_nb_P3D_vel_gaussian												\n"
"	CVTX_P3D_VEL_START																\n"
"	const float pi = 3.14159265359f;												\n"
"	float a1 = 0.254829592f, a2 = -0.284496736f, a3 = 1.421413741f;					\n"
"	float a4 = -1.453152027f, a5 = 1.061405429f, p = 0.3275911f;					\n"
"	float rho_sr2 = rho / sqrt(2.f);												\n"
"	float t = 1.f / (1.f + p * rho_sr2);											\n"
"	float t2 = t * t;	float t3 = t2 * t; float t4 = t2 * t2; float t5 = t3 * t2;	\n"
"	float erf = 1.f - (a1 * t + a2 * t2 + a3 * t3 + a4 * t4 + a5 * t5) *			\n"
"		exp(-rho_sr2 * rho_sr2);													\n"
"	float term2 = rho * SQRT_2_OVER_PI * exp(-rho_sr2 * rho_sr2);					\n"
"	g = erf - term2;																\n"
"	CVTX_P3D_VEL_END																\n"



/* ###########################################################
	3D Ind Dvort calculation kernels here:
	name cvtx_nb_P3D_dvort_XXXXX
	###########################################################	*/	

"__kernel void cvtx_nb_P3D_dvort_singular\n"
"	CVTX_P3D_DVORT_START\n"
"	g = 1.f;\n"
"	f = 0.f;\n"
"	CVTX_P3D_DVORT_END\n"


"__kernel void cvtx_nb_P3D_dvort_planetary\n"
"	CVTX_P3D_DVORT_START\n"
"	g = rho < 1.f ? rho * rho * rho : 1.f;\n"
"	f = rho < 1.f ? 3.f : 0.f;\n"
"	CVTX_P3D_DVORT_END\n"


"__kernel void cvtx_nb_P3D_dvort_winckelmans\n"
"	CVTX_P3D_DVORT_START\n"
"	g = (rho * rho + 2.5f) * rho * rho * rho * rsqrt(pown(rho * rho + 1, 5));		\n"
"	f = 7.5f * rsqrt(pown(rho * rho + 1, 7));										\n"
"	CVTX_P3D_DVORT_END\n"


"__kernel void cvtx_nb_P3D_dvort_gaussian\n"
"	CVTX_P3D_DVORT_START															\n"
"	const float pi = 3.14159265359f;												\n"
"	float a1 = 0.254829592f, a2 = -0.284496736f, a3 = 1.421413741f;					\n"
"	float a4 = -1.453152027f, a5 = 1.061405429f, p = 0.3275911f;					\n"
"	float rho_sr2 = rho * ONE_OVER_SQRT_TWO;												\n"
"	float t = 1.f / (1.f + p * rho_sr2);											\n"
"	float t2 = t * t;	float t3 = t2 * t; float t4 = t2 * t2; float t5 = t3 * t2;	\n"
"	float erf = 1.f - (a1 * t + a2 * t2 + a3 * t3 + a4 * t4 + a5 * t5) *			\n"
"		exp(-rho_sr2 * rho_sr2);													\n"
"	float term2 = rho * SQRT_2_OVER_PI * exp(-rho_sr2 * rho_sr2);					\n"
"	g = erf - term2;																\n"
"	f = SQRT_2_OVER_PI * exp(-rho * rho * 0.5f);									\n"
"	CVTX_P3D_DVORT_END																\n"


/* ###########################################################
	3D viscous ind Dvort calculation kernels here:
	name cvtx_nb_P3D_visc_dvort_XXXXX	
	###########################################################	*/

"	/* Viscocity doesn't work for singular & planetary */							\n"

"__kernel void cvtx_nb_P3D_visc_dvort_winckelmans									\n"
"	CVTX_P3D_VISC_DVORT_START														\n"
"	eta = 52.5f * rsqrt(pown(rho * rho + 1, 9));									\n"
"	CVTX_P3D_VISC_DVORT_END															\n"


"__kernel void cvtx_nb_P3D_visc_dvort_gaussian										\n"
"	CVTX_P3D_VISC_DVORT_START														\n"
"	const float pi = 3.14159265359f;												\n"
"	eta = SQRT_2_OVER_PI * exp(-rho * rho * 0.5f);									\n"
"	CVTX_P3D_VISC_DVORT_END															\n"


/* ###########################################################
	3D vorticity calculation kernels here:
	name cvtx_nb_P3D_vort_XXXXX	
	###########################################################	*/

"__kernel void cvtx_nb_P3D_vort_singular\n"/* Arguably, what is the point? */
"	CVTX_P3D_VORT_START														\n"
"	zeta = 0.f;																\n"
"	CVTX_P3D_VORT_END														\n"


"__kernel void cvtx_nb_P3D_vort_winckelmans									\n"
"	CVTX_P3D_VORT_START														\n"
"	zeta = 7.5f * pow(rho*rho+1, -3.5f);									\n"
"	CVTX_P3D_VORT_END														\n"


"__kernel void cvtx_nb_P3D_vort_planetary									\n"
"	CVTX_P3D_VORT_START														\n"
"	zeta = rho < 1.f ? 3.f : 0.f;											\n"
"	CVTX_P3D_VORT_END														\n"


"__kernel void cvtx_nb_P3D_vort_gaussian									\n"
"	CVTX_P3D_VORT_START														\n"
"	zeta = SQRT_2_OVER_PI * exp(-rho * rho * 0.5f);							\n"
"	CVTX_P3D_VORT_END														\n"


/* 	###########################################################
	2DVelocity calculation kernels here:
	name cvtx_nb_P2D_vel_XXXXX
	###########################################################	*/

"__kernel void cvtx_nb_P2D_vel_singular\n"
"	CVTX_P2D_VEL_START														\n"
"	g = 1.f;																\n"
"	CVTX_P2D_VEL_END														\n"

"__kernel void cvtx_nb_P2D_vel_winckelmans									\n"
"	CVTX_P2D_VEL_START														\n"
"	g = (rho * rho + 2.0f) * rho * rho * pown(rho * rho + 1.f, -2);			\n"
"	CVTX_P2D_VEL_END														\n"

"__kernel void cvtx_nb_P2D_vel_planetary									\n"
"	CVTX_P2D_VEL_START														\n"
"	g = rho < 1.f ? rho * rho : 1.f;										\n"
"	CVTX_P2D_VEL_END														\n"

"__kernel void cvtx_nb_P2D_vel_gaussian										\n"
"	CVTX_P2D_VEL_START														\n"
"	g = 1.f - exp(-rho * rho * 0.5f);										\n"
"	CVTX_P2D_VEL_END														\n"

/* Small number of mes points. */
"__kernel void cvtx_nb_P2D_smallmes_vel_singular							\n"
"	CVTX_P2D_SMALLMES_VEL_START												\n"
"	g = 1.f;																\n"
"	CVTX_P2D_SMALLMES_VEL_END												\n"

"__kernel void cvtx_nb_P2D_smallmes_vel_winckelmans							\n"
"	CVTX_P2D_SMALLMES_VEL_START												\n"
"	g = (rho * rho + 2.0f) * rho * rho * pown(rho * rho + 1.f, -2);			\n"
"	CVTX_P2D_SMALLMES_VEL_END												\n"

"__kernel void cvtx_nb_P2D_smallmes_vel_planetary							\n"
"	CVTX_P2D_SMALLMES_VEL_START												\n"
"	g = rho < 1.f ? rho * rho : 1.f;										\n"
"	CVTX_P2D_SMALLMES_VEL_END												\n"

"__kernel void cvtx_nb_P2D_smallmes_vel_gaussian							\n"
"	CVTX_P2D_SMALLMES_VEL_START												\n"
"	g = 1.f - exp(-rho * rho * 0.5f);										\n"
"	CVTX_P2D_SMALLMES_VEL_END												\n"

/* ###########################################################
	2D viscous ind Dvort calculation kernels here:
	name cvtx_nb_P2D_visc_dvort_XXXXX	
	###########################################################	*/

"	/* Viscocity doesn't work for singular & planetary */							\n"

"__kernel void cvtx_nb_P2D_visc_dvort_winckelmans									\n"
"	CVTX_P2D_VISC_DVORT_START														\n"
"	float a = rho * rho + 1.f;														\n"
"	float a2 = 1.f / (a * a);														\n"
"	eta = 24.f * exp(4.f * a * (a2 * a2)) * (a2 * a2);								\n"
"	CVTX_P2D_VISC_DVORT_END															\n"

"__kernel void cvtx_nb_P2D_visc_dvort_gaussian										\n"
"	CVTX_P2D_VISC_DVORT_START														\n"
"	eta =  exp(-rho * rho * 0.5f);													\n"
"	CVTX_P2D_VISC_DVORT_END															\n"

/*	###########################################################
	vortex_filament code:
	###########################################################	*/

"__kernel void cvtx_nb_Filament_ind_vel_singular									\n"
"(																					\n"
"	__global float3* fil_starts,													\n"
"	__global float3* fil_ends,														\n"
"	__global float* fil_strengths,													\n"
"	__global float3* mes_pnts,														\n"
"	__global float3* results)														\n"
"{																					\n"
"	float3 ret, r0, r1, r2;															\n"
"	float t1, t2, t21, t22;															\n"
"	const float pi_f = 3.14159265359f;												\n"
"	const float bigvar = 3.40282346e38f;											\n"
/* fidx: filament index, midx: measurement index */
"	uint fidx, midx, loop_idx;														\n"
"	fidx = get_global_id(0);														\n"
"	midx = get_global_id(1);														\n"
"	r1 = mes_pnts[midx] - fil_starts[fidx];											\n"
"	r2 = mes_pnts[midx] - fil_ends[fidx];											\n"
"	r0 = r1 - r2;																	\n"
"	t1 = fil_strengths[fidx] / (4 * pi_f * pown(length(cross(r1,r2)), 2));			\n"
"	t21 = dot(r1, r0) / length(r1);													\n"
"	t22 = dot(r2, r0) / length(r2);													\n"
"	t2 = t21 - t22;																	\n"
"	ret = cross(r1, r2) * t1 * t2;													\n"
/* 	If t1 * t2 is a really big number then the cross product is dodgy, meaning that
	r1 & r2 are almost parallel or parallel. We want to ignore this on axis stuff. 	*/
"	ret = fabs(t1) <= bigvar && fabs(t2) <= bigvar ? ret : (float3)(0.f, 0.f, 0.f);	\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];						\n"
"	reduction_workspace[fidx] = ret;												\n"
"	local_workspace_float3_reduce(reduction_workspace);								\n"
"	barrier(CLK_LOCAL_MEM_FENCE);													\n"
"	if( fidx == 0 ){																\n"
"		results[midx] = reduction_workspace[0] + results[midx];						\n"
"	}																				\n"
"	return;																			\n"
"}																					\n"

/* A kernel for when there are fewer measurement points. */
"__kernel void cvtx_nb_Filament_ind_vel_singular_smes								\n"
"(																					\n"
"	__global float3* fil_starts,													\n"
"	__global float3* fil_ends,														\n"
"	__global float* fil_strengths,													\n"
"	__global float3* mes_pnts,														\n"
"	__global float3* results,														\n"
"	unsigned int num_mes)															\n"
"{																					\n"
"	float3 ret, r0, r1, r2;															\n"
"	float t1, t2, t21, t22;															\n"
"	const float pi_f = (float)3.14159265359;										\n"
"	const float bigvar = 3.40282346e38f;											\n"
/* fidx: filament index, midx: measurement index */	
"	uint fidx, midx, gidx, loop_idx;												\n"
"	midx = get_global_id(1);														\n"
"	gidx = get_global_id(0);														\n"
"	fidx = gidx + CVTX_CL_WORKGROUP_SIZE * (midx / num_mes);						\n"
"	r1 = mes_pnts[midx] - fil_starts[fidx];											\n"
"	r2 = mes_pnts[midx] - fil_ends[fidx];											\n"
"	r0 = r1 - r2;																	\n"
"	t1 = fil_strengths[fidx] / (4 * pi_f * pown(length(cross(r1,r2)), 2));			\n"
"	t21 = dot(r1, r0) / length(r1);													\n"
"	t22 = dot(r2, r0) / length(r2);													\n"
"	t2 = t21 - t22;																	\n"
"	ret = cross(r1, r2) * t1 * t2;													\n"
"	ret = fabs(t1) <= bigvar && fabs(t2) <= bigvar ? ret : (float3)(0.f, 0.f, 0.f);	\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];						\n"
"	reduction_workspace[gidx] = ret;												\n"
"	local_workspace_float3_reduce(reduction_workspace);								\n"
"	barrier(CLK_LOCAL_MEM_FENCE);													\n"
"	if( gidx == 0 ){																\n"
"		results[midx] = reduction_workspace[0];										\n"
"	}																				\n"
"	return;																			\n"
"}																					\n"

"__kernel void cvtx_nb_Filament_ind_dvort_singular									\n"
"(																					\n"
"	__global float3* fil_starts,													\n"
"	__global float3* fil_ends,														\n"
"	__global float* fil_strengths,													\n"
"	__global float3* particle_locs,													\n"
"	__global float3* particle_vorts,												\n"
"	__global float3* results)														\n"
"{																					\n"
"	float3 ret, r0, r1, r2, t211, A, tmp;											\n"
"	float t1, t2121, t2122, t212, t221, t222, t2221, t2222, B, crosslen;			\n"
"	const float pi_f = (float)3.14159265359;										\n"
/* fidx: filament index, pidx: particle index */
"	uint fidx, pidx, loop_idx;														\n"
"	fidx = get_global_id(0);														\n"
"	pidx = get_global_id(1);														\n"
"	r1 = particle_locs[pidx] - fil_starts[fidx];									\n"
"	r2 = particle_locs[pidx] - fil_ends[fidx];										\n"
"	r0 = r1 - r2;																	\n"
"	t1 = fil_strengths[fidx] / (4.f * pi_f);										\n"
"	crosslen = pown(length(cross(r1, r0)), 2);										\n"
"	t211 = -r0 / crosslen;															\n"
"	t2121 = dot(r0, r1) / length(r1);												\n"
"	t2122 = -dot(r0, r2) / length(r2);												\n"
" 	t221 = 3.0f / length(r0);														\n"
"	t2221 = length(cross(r0, r1)) / length(r1);										\n"
"	t2222 = -length(cross(r0, r1)) / length(r2);									\n"
"	t222 = t2221 + t2222;															\n"
"	t212 = t2121 + t2122;															\n"
"	A = t211 * t1 * t212;															\n"
"	B = t221 * t1 * t222;															\n"
"	ret = B * particle_vorts[pidx] + cross(A, particle_vorts[pidx]);				\n"
"	ret = !(ret == ret) || (t222 != t222) || (t212 != t212) ?						\n"
"							(float3)(0.f, 0.f, 0.f) : ret;							\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];						\n"
"	reduction_workspace[fidx] = ret;												\n"
"	/* Now sum to a single value. */												\n"
"	local_workspace_float3_reduce(reduction_workspace);								\n"
"	barrier(CLK_LOCAL_MEM_FENCE);													\n"
"	if( fidx == 0 ){																\n"
"		results[pidx] = reduction_workspace[0] + results[pidx];						\n"
"	}																				\n"
"	return;																			\n"
"}																					\n"
