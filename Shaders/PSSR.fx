/*------------------.
| :: Description :: |
'-------------------/

    PRSSR  (Version 0.1)

    Author: Barbatos Bachiko
    License: MIT

    About: Planar reflections with ray marching.

    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility
*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

uniform int debugMode
    <
        ui_type = "combo";
        ui_label = "Debug Mode";
        ui_tooltip = "Select a debug mode to visualize different aspects of the reflection.";
        ui_items = 
    "None\0" 
    "Depth Map\0";
    >
    = 0;

uniform float reflectionIntensity
    <
        ui_type = "slider";
        ui_label = "Reflection Intensity";
        ui_tooltip = "Adjust the intensity.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
    >
    = 0.02;

uniform float sampleRadius
    <
        ui_type = "slider";
        ui_label = "Sample Radius";
        ui_tooltip = "Adjust the radius of the samples";
        ui_min = 0.001; ui_max = 5.0; ui_step = 0.001;
    >
    = 0.500;

uniform int sampleSteps
    <
        ui_type = "slider";
        ui_label = "Sample Steps";
        ui_tooltip = "Adjust the number of steps for ray marching.";
        ui_min = 1; ui_max = 60; ui_step = 1;
    >
    = 35; 

/*---------------.
| :: Textures :: |
'---------------*/

namespace PlanarReflection
{
    texture ColorTex : COLOR;
    texture DepthTex : DEPTH;
    sampler ColorSampler
    {
        Texture = ColorTex;
    };
    sampler DepthSampler
    {
        Texture = DepthTex;
    };

    /*----------------.
    | :: Functions :: |
    '----------------*/

    float3 FresnelReflectance(float3 viewDir, float3 normal, float reflectance = 0.04)
    {
        float3 F0 = float3(reflectance, reflectance, reflectance);
        float cosTheta = max(dot(viewDir, normal), 0.0);
        return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    }

    float3 ReflectRay(float3 rayDir, float3 normal)
    {
        return rayDir - 2.0 * dot(rayDir, normal) * normal;
    }
    
    float SampleDepth(float2 coord)
    {
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
        coord.y = 1.0 - coord.y;  // Correct depth inversion if needed
#endif
        return tex2D(DepthSampler, clamp(coord, 0.0, 1.0)).r;
    }

    float3 RayMarching(float2 texcoord, float3 rayDir, float radius, int steps, out float debugDepth)
    {
        float3 indirectColor = float3(0.0, 0.0, 0.0);
        float depthValue = SampleDepth(texcoord); 
        float2 sampleCoord;
        float sampleDepth;
        float stepSize = radius * 0.001;
        debugDepth = 0.0;

        for (int i = 1; i <= steps; ++i)
        {
            sampleCoord = texcoord + rayDir.xy * (i * stepSize);
            sampleCoord = clamp(sampleCoord, 0.0, 1.0);
            sampleDepth = SampleDepth(sampleCoord); 
            debugDepth = sampleDepth; 

            if (sampleDepth < depthValue)
                indirectColor += tex2D(ColorSampler, sampleCoord).rgb;
        }

        return indirectColor;
    }

    float4 PlanarReflection(float2 texcoord, float3 cameraPos, float3 reflectionPlaneNormal, float reflectionHeight, float radius)
    {
        float4 originalColor = tex2D(ColorSampler, texcoord);
        float3 indirectColor = float3(0.0, 0.0, 0.0);
        float3 reflectionRayDir = ReflectRay(cameraPos, reflectionPlaneNormal);
        float debugDepth = 0.0;
        indirectColor = RayMarching(texcoord, reflectionRayDir, radius, sampleSteps, debugDepth);
        indirectColor *= reflectionIntensity;
        return float4(originalColor.rgb + indirectColor, 1.0);
    }

    float4 PlanarReflectionPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float3 cameraPos = float3(0.0, 10.0, 0.0);
        float3 reflectionPlaneNormal = float3(0.0, 1.0, 0.0);
        float reflectionHeight = 0.0;
        float4 planarReflectionColor = PlanarReflection(texcoord, cameraPos, reflectionPlaneNormal, reflectionHeight, sampleRadius);
        
        if (debugMode == 1) 
        {
            float depthValue = SampleDepth(texcoord);
            return float4(depthValue, depthValue, depthValue, 1.0);
        }

        return planarReflectionColor;
    }
    
    void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
    {
        texcoord = float2((id == 2) ? 2.0 : 0.0, (id == 1) ? 2.0 : 0.0);
        position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    /*-----------------.
    | :: Techniques :: |
    '-----------------*/

    technique PRSSR
    {
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = PlanarReflectionPS;
        }
    }
}
