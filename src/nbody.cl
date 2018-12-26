"/*============================================================================\n"
"nbody.cl\n"

"OpenCL implementation of vortex particle N-Body problem using brute force.\n"

"Copyright(c) 2018 HJA Bird\n"

"Permission is hereby granted, free of charge, to any person obtaining a copy\n"
"of this software and associated documentation files(the \"Software\"), to deal\n"
"in the Software without restriction, including without limitation the rights\n"
"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
"copies of the Software, and to permit persons to whom the Software is\n"
"furnished to do so, subject to the following conditions :\n"

"The above copyright notice and this permission notice shall be included in all\n"
"copies or substantial portions of the Software.\n"

"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE\n"
"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
"SOFTWARE.\n"
"============================================================================*/\n"
"/* CVTX_CL_WORKGROUP_SIZE controlled with build options from host */\n"
"/* CVTX_CL_REDUCTION_TYPE controlled with build options from host */\n"
"\n"
"/*############################################################################\n"
"Definitions for the repeated body of kernels\n"
"############################################################################*/\n"
"\n"
"#define CVTX_P_INDVEL_START 										\\\n"
"(																	\\\n"
"	__global float3* particle_locs,									\\\n"
"	__global float3* particle_vorts,								\\\n"
"	float   regularisation_rad,							            \\\n"
"	__global float3* mes_locs,										\\\n"
"	__global float3* results)										\\\n"
"{																	\\\n"
"	float3 rad, num, ret;											\\\n"
"	float cor, den, rho, g;											\\\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];	\\\n"
"	/* Particle idx, mes_pnt idx and local work item idx */			\\\n"
"	uint pidx, midx, widx, loop_idx;								\\\n"
"	pidx = get_global_id(0);										\\\n"
"	midx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	if(all(isequal(particle_locs[pidx], mes_locs[midx]))){			\\\n"
"		ret.x = 0.0f;												\\\n"
"		ret.y = 0.0f;												\\\n"
"		ret.z = 0.0f;												\\\n"
"	}																\\\n"
"	else 															\\\n"
"	{																\\\n"
"		rad = mes_locs[midx] - particle_locs[pidx];					\\\n"
"		rho = length(rad) / regularisation_rad;    					\n"

"		/* Fill in g calc here */\n"

"#define CVTX_P_INDVEL_END 											\\\n"
"		cor = - g / (4 * acos((float)-1));							\\\n"
"		den = pown(length(rad), 3);									\\\n"
"		num = cross(rad, particle_vorts[pidx]);						\\\n"
"		ret = num * (cor / den);									\\\n"
"	}																\\\n"
"	reduction_workspace[widx] = convert_float3(ret);				\\\n"
"	/* Now sum to a single value. */								\\\n"
"	for(loop_idx = 2; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 			\\\n"
"		loop_idx *= 2){												\\\n"
"		barrier(CLK_LOCAL_MEM_FENCE);								\\\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){				\\\n"
"			reduction_workspace[widx] = reduction_workspace[widx] 	\\\n"
"				+  reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\\\n"
"		}															\\\n"
"	}																\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[midx] = reduction_workspace[0] + results[midx];		\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

"#define CVTX_P_IND_DVORT_START										\\\n"
"(																	\\\n"
"	__global float3* particle_locs,									\\\n"
"	__global float3* particle_vorts,								\\\n"
"	float    regularisation_dist,	        						\\\n"
"	__global float3* induced_locs,									\\\n"
"	__global float3* induced_vorts,									\\\n"
"	__global float3* results)										\\\n"
"{																	\\\n"
"	float3 ret, rad, cross_om, t2, t21, t21n, t22, t224;			\\\n"
"	float g, f, radd, rho, t1, t21d, t221, t222, t223;				\\\n"
"	__local float3 reduction_workspace[CVTX_CL_WORKGROUP_SIZE];	\\\n"
"	/* self (inducing particle) index, induced particle index */	\\\n"
"	uint sidx, indidx, widx, loop_idx;								\\\n"
"	sidx = get_global_id(0);										\\\n"
"	indidx = get_global_id(1);										\\\n"
"	widx = get_local_id(0);											\\\n"
"	if(all(isequal(particle_locs[sidx], induced_locs[indidx]))){	\\\n"
"		ret.x = 0.0f;											\\\n"
"		ret.y = 0.0f;											\\\n"
"		ret.z = 0.0f;											\\\n"
"	}																\\\n"
"	else 															\\\n"
"	{																\\\n"
"		rad = induced_locs[indidx] - particle_locs[sidx];			\\\n"
"		radd = length(rad);											\\\n"
"		rho = radd / regularisation_dist;  							\n"

"		/* FILL in f & g calc here! */\n"

"#define CVTX_P_IND_DVORT_END										\\\n"
"		cross_om = cross(induced_vorts[indidx], 					\\\n"
"			particle_vorts[sidx]);									\\\n"
"		t1 = 1.f / (4. * acos((float)-1) * powr(regularisation_dist, 3));\\\n"
"		t21n = cross_om * -g;										\\\n"
"		t21d = rho * rho * rho;										\\\n"
"		t21 = t21n / t21d;											\\\n"
"		t221 = 1.f / (radd * radd);									\\\n"
"		t222 = (3 * g) / (rho * rho * rho) - f;						\\\n"
"		t223 = dot(induced_vorts[indidx], rad);						\\\n"
"		t224 = cross(rad, particle_vorts[sidx]);					\\\n"
"		t22 = t224 * t221 * t222 * t223;							\\\n"
"		t2 = t21 + t22;												\\\n"
"		ret = t2 * t1;												\\\n"
"	}																\\\n"
"	reduction_workspace[widx] = convert_float3(ret);				\\\n"
"	/* Now sum to a single value. */								\\\n"
"	for(loop_idx = 2; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 			\\\n"
"		loop_idx *= 2){												\\\n"
"		barrier(CLK_LOCAL_MEM_FENCE);								\\\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){				\\\n"
"			reduction_workspace[widx] = reduction_workspace[widx] 	\\\n"
"				+  reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\\\n"
"		}															\\\n"
"	}																\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[indidx] = reduction_workspace[0] + results[indidx];	\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"

"float sphere_volume(float radius){									\n"
"	return 4 * acos((float)-1) * radius * radius * radius / 3.f;    \n"
"}																	\n"

"#define CVTX_P_VISC_IND_DVORT_START								\\\n"
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
"	if(all(isequal(particle_locs[sidx], induced_locs[indidx]))){	\\\n"
"		ret.x = 0.0f;											\\\n"
"		ret.y = 0.0f;											\\\n"
"		ret.z = 0.0f;											\\\n"
"	}																\\\n" 
"	else {															\\\n"
"		rad = particle_locs[sidx] - induced_locs[indidx];			\\\n"
"		radd = length(rad);											\\\n"
"		rho = radd / regularisation_dist;							\\\n"
"		t1 =  2 * kinematic_visc / pown(regularisation_dist, 2);	\\\n"
"		t211 = particle_vorts[sidx] * induced_vols[indidx];  		\\\n"
"		t212 = induced_vorts[indidx] * -1 * particle_vols[sidx];	\\\n"
"		t21 = t211 + t212;											\n"

"		/* ETA FUNCTION function!  here */							"

"#define CVTX_P_VISC_IND_DVORT_END									\\\n"
"		t2 = t21 * eta;												\\\n"
"		ret = t2 * t1;												\\\n"
"	}																\\\n"
"	reduction_workspace[widx] = convert_float3(ret);				\\\n"
"	/* Now sum to a single value. */								\\\n"
"	for(loop_idx = 2; loop_idx <= CVTX_CL_WORKGROUP_SIZE; 			\\\n"
"		loop_idx *= 2){												\\\n"
"		barrier(CLK_LOCAL_MEM_FENCE);								\\\n"
"		if( widx < CVTX_CL_WORKGROUP_SIZE/loop_idx ){				\\\n"
"			reduction_workspace[widx] = reduction_workspace[widx] 	\\\n"
"				+  reduction_workspace[widx + CVTX_CL_WORKGROUP_SIZE/loop_idx];\\\n"
"		}															\\\n"
"	}																\\\n"
"	barrier(CLK_LOCAL_MEM_FENCE);									\\\n"
"	if( widx == 0 ){												\\\n"
"		results[indidx] = reduction_workspace[0] + results[indidx];	\\\n"
"	}																\\\n"
"	return;															\\\n"
"}																	\n"



"/* ###########################################################	*/	\n"
"/* Velocity calculation kernels here:							*/	\n"
"/* name cvtx_nb_Particle_ind_vel_XXXXX							*/	\n"
"/* ###########################################################	*/	\n"

"__kernel void cvtx_nb_Particle_ind_vel_singular\n"
"	CVTX_P_INDVEL_START\n"
"	g = 1.f;\n"
"	CVTX_P_INDVEL_END\n"


"__kernel void cvtx_nb_Particle_ind_vel_winckelmans\n"
"	CVTX_P_INDVEL_START\n"
"	g = (rho * rho + 2.5f) * rho * rho * rho / powr(rho * rho + 1, 2.5f);\n"
"	CVTX_P_INDVEL_END\n"


"__kernel void cvtx_nb_Particle_ind_vel_planetary\n"
"	CVTX_P_INDVEL_START\n"
"	g = rho < 1.f ? rho * rho * rho : 1.f;\n"
"	CVTX_P_INDVEL_END\n"


"__kernel void cvtx_nb_Particle_ind_vel_gaussian\n"
"	CVTX_P_INDVEL_START\n"
"	if(rho > 6.f){\n"
"		g = 1.f;\n"
"	} else {\n"
"		const float pi = 3.14159265359f;\n"
"		float a1 = 0.3480242f, a2 = -0.0958798f, a3 = 0.7478556f, p = 0.47047f;		\n"
"		float rho_sr2 = rho / sqrt(2.f);										\n"
"		float t = 1.f / (1 + p * rho_sr2);									\n"
"		float erf = 1.f-t * (a1 + t * (a2 + t * a3)) * exp(-rho_sr2 * rho_sr2);		\n"
"		float term2 = rho * sqrt((float)2 / pi) * exp(-rho_sr2 * rho_sr2);			\n"
"		g = erf - term2;															\n"
"	}																				\n"
"	CVTX_P_INDVEL_END\n"



"/* ###########################################################	*/	\n"
"/* Ind Dvort calculation kernels here:							*/	\n"
"/* name cvtx_nb_Particle_ind_dvort_XXXXX						*/	\n"
"/* ###########################################################	*/	\n"

"__kernel void cvtx_nb_Particle_ind_dvort_singular\n"
"	CVTX_P_IND_DVORT_START\n"
"		g = 1.f;\n"
"		f = 0.f;\n"
"	CVTX_P_IND_DVORT_END\n"


"__kernel void cvtx_nb_Particle_ind_dvort_planetary\n"
"	CVTX_P_IND_DVORT_START\n"
"		g = rho < 1.f ? rho * rho * rho : (float)1.;\n"
"		f = rho < 1.f ? (float)3 : (float)0;\n"
"	CVTX_P_IND_DVORT_END\n"


"__kernel void cvtx_nb_Particle_ind_dvort_winckelmans\n"
"	CVTX_P_IND_DVORT_START\n"
"		g = (rho * rho + (float)2.5) * rho * rho * rho / powr(rho * rho + 1, (float)2.5);	\n"
"		f = (float)7.5 / powr(rho * rho + 1, (float)3.5);									\n"
"		/*f = (float)52.5 * pow(rho * rho + 1, (float)-4.5);*/									\n"
"	CVTX_P_IND_DVORT_END\n"


"__kernel void cvtx_nb_Particle_ind_dvort_gaussian\n"
"	CVTX_P_IND_DVORT_START															\n"
"	const float pi = 3.14159265359f;												\n"
"	if(rho > (float)6.){															\n"
"		g = 1.f;																	\n"
"	} else {																		\n"
"		float a1 = 0.3480242f, a2 = -0.0958798f, a3 = 0.7478556f, p = 0.47047f;		\n"
"		float rho_sr2 = rho / sqrt((float)2);										\n"
"		float t = (float) 1. / (1 + p * rho_sr2);									\n"
"		float erf = 1.f-t * (a1 + t * (a2 + t * a3)) * exp(-rho_sr2 * rho_sr2);		\n"
"		float term2 = rho * sqrt((float)2 / pi) * exp(-rho_sr2 * rho_sr2);			\n"
"		g = erf - term2;															\n"
"	}																				\n"
"	f =  sqrt((float) 2 / pi) * exp(-rho * rho / 2);								\n"
"	CVTX_P_IND_DVORT_END															\n"


"/* ###########################################################	*/	\n"
"/* viscous ind Dvort calculation kernels here:					*/	\n"
"/* name cvtx_nb_Particle_visc_ind_dvort_XXXXX					*/	\n"
"/* ###########################################################	*/	\n"

"	/* Viscocity doesn't work for singular & planetary */							\n"

"__kernel void cvtx_nb_Particle_visc_ind_dvort_winckelmans							\n"
"	CVTX_P_VISC_IND_DVORT_START														\n"
"		eta = (float)52.5 * pow(rho * rho + 1, (float)-4.5);						\n"
"	CVTX_P_VISC_IND_DVORT_END														\n"


"__kernel void cvtx_nb_Particle_visc_ind_dvort_gaussian								\n"
"	CVTX_P_VISC_IND_DVORT_START														\n"
"		const float pi = 3.14159265359f;											\n"
"		eta =  sqrt((float) 2.f / pi) * exp(-rho * rho / 2.f);						\n"
"	CVTX_P_VISC_IND_DVORT_END														\n"
