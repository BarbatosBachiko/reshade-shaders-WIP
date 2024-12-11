/*------------------.
| :: Description :: |
'-------------------/

   RGIAO (Version 0.1)

    Author: Barbatos Bachiko
    License: MIT

    About: Implements planar reflections, diffuse global illumination with ray marching, and ambient occlusion.

    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility
*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

uniform int viewMode
    <
        ui_type = "combo";
        ui_label = "View Mode";
        ui_tooltip = "Select the view mode for RMGI";
        ui_items = 
    "Normal\0" 
    "Reflection Debug\0"
    "AO Debug\0";
    >
    = 0;

uniform float reflectionIntensity
    <
        ui_type = "slider";
        ui_label = "Reflection Intensity";
        ui_tooltip = "Adjust the intensity of the planar reflection.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
    >
    = 0.02;

uniform float sampleRadius
    <
        ui_type = "slider";
        ui_label = "Sample Radius";
        ui_tooltip = "Adjust the radius of the samples for global illumination";
        ui_min = 0.001; ui_max = 5.0; ui_step = 0.001;
    >
    = 0.500;

uniform int sampleSteps
    <
        ui_type = "slider";
        ui_label = "Sample Steps";
        ui_tooltip = "Adjust the number of steps for ray marching.";
        ui_min = 0.001; ui_max = 50.0; ui_step = 0.001;
    >
    = 4; 

uniform float aoIntensity
    <
        ui_type = "slider";
        ui_label = "AO Intensity";
        ui_tooltip = "Adjust the strength of the ambient occlusion.";
        ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
    >
    = 1.2;

uniform float aoRadius
    <
        ui_type = "slider";
        ui_label = "AO Radius";
        ui_tooltip = "Adjust the radius for ambient occlusion sampling.";
        ui_min = 0.01; ui_max = 3.0; ui_step = 0.01;
    >
    = 0.01;

uniform int aoSteps
    <
        ui_type = "slider";
        ui_label = "AO Steps";
        ui_tooltip = "Adjust the number of steps used to calculate ambient occlusion.";
        ui_min = 1; ui_max = 50; ui_step = 1;
    >
    = 50;

uniform int maxBounces
<
    ui_type = "slider";
    ui_label = "Max Bounces";
    ui_tooltip = "Number of bounces for diffuse GI";
    ui_min = 1; ui_max = 10; ui_step = 1;
>
= 10;


/*---------------.
| :: Textures :: |
'---------------*/

namespace RGIAO
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

    // Fresnel Reflection Calculation
    float3 Fresnel(float3 viewDir, float3 normal, float reflectance = 0.04)
    {
        float3 F0 = float3(reflectance, reflectance, reflectance);
        float cosTheta = max(dot(viewDir, normal), 0.0);
        return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    }

    // Reflect the ray
    float3 Reflect(float3 rayDir, float3 normal)
    {
        return rayDir - 2.0 * dot(rayDir, normal) * normal;
    }

    // Ray Marching for Diffuse GI
    float3 RayMarchGI(float2 texcoord, float3 rayDir, float radius, int steps)
    {
        float3 indirectColor = float3(0.0, 0.0, 0.0);
        float depthValue = tex2D(DepthSampler, texcoord).r;
        float2 sampleCoord;
        float sampleDepth;
        float stepSize = radius * 0.001;
        
        if (steps > 0)
        {
            for (int i = 1; i <= steps; i++)
            {
                sampleCoord = texcoord + rayDir.xy * (i * stepSize);
                sampleCoord = clamp(sampleCoord, 0.0, 1.0);
                sampleDepth = tex2D(DepthSampler, sampleCoord).r;
                if (sampleDepth < depthValue)
                {
                    indirectColor += tex2D(ColorSampler, sampleCoord).rgb;
                }
            }
        }

        return indirectColor;
    }

    // GI with Bounces
    float3 GIWithBounces(float2 texcoord, float3 initialRayDir, float radius, int steps, int maxBounces)
    {
        float3 totalIndirectColor = float3(0.0, 0.0, 0.0);
        float3 currentRayDir = initialRayDir;

        for (int bounce = 0; bounce < maxBounces; bounce++)
        {
            float3 bounceIndirectColor = RayMarchGI(texcoord, currentRayDir, radius, steps);
            totalIndirectColor += bounceIndirectColor;
            currentRayDir = normalize(float3(
            sin(bounce * 12.9898 + 78.233),
            cos(bounce * 78.233 + 45.987),
            sin(bounce * 3.14)
        ));
        }

        return totalIndirectColor;
    }

    // Ambient Occlusion Calculation
    float AO(float2 texcoord, float3 normal, float radius, int steps)
    {
        float ao = 0.0;
        float depthValue = tex2D(DepthSampler, texcoord).r;
        float2 sampleCoord;
        float sampleDepth;
        float stepSize = radius * 0.001;
        float3 randomDir;
        float3 stepRay;
        float dynamicStepSize = radius * (1.0 - depthValue);
        
        if (steps > 0)
        {
            for (int i = 0; i < steps; i++)
            {
                randomDir = float3(sin(i * 12.9898), cos(i * 78.233), sin(i * 3.14));
                stepRay = texcoord + randomDir.xy * (i * dynamicStepSize);
                stepRay = clamp(stepRay, 0.0, 1.0);
                sampleDepth = tex2D(DepthSampler, stepRay).r;
                if (sampleDepth < depthValue)
                {
                    ao += 1.0;
                }
            }
        }
        ao = 1.0 - (ao / steps);
        return ao;
    }

    // Planar Reflection Calculation
    float4 Reflection(float2 texcoord, float3 cameraPos, float3 planeNormal, float planeHeight, float radius)
    {
        float4 originalColor = tex2D(ColorSampler, texcoord);
        float3 reflectionRayDir = Reflect(cameraPos, planeNormal);
        float3 reflectionColor = GIWithBounces(texcoord, reflectionRayDir, radius, sampleSteps, maxBounces);
        reflectionColor *= reflectionIntensity;
        return float4(originalColor.rgb + reflectionColor, 1.0);
    }

    // Main Pixel Shader
    float4 MainPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float3 cameraPos = float3(0.0, 10.0, 0.0);
        float3 planeNormal = float3(0.0, 1.0, 0.0);
        float planeHeight = 0.0;
        float4 reflectionColor = Reflection(texcoord, cameraPos, planeNormal, planeHeight, sampleRadius);
        float ao = AO(texcoord, planeNormal, aoRadius, aoSteps);
        ao = lerp(1.0, ao, aoIntensity);
        float3 finalColor = reflectionColor.rgb * ao;

        // View Modes
        if (viewMode == 0)  // Normal View
        {
            return float4(finalColor, 1.0);
        }
        else if (viewMode == 1)  // Reflection Debug View
        {
            float3 reflectionDebug = GIWithBounces(texcoord, Reflect(cameraPos, planeNormal), sampleRadius, sampleSteps, maxBounces);
            reflectionDebug *= reflectionIntensity;
            return float4(reflectionDebug, 1.0);
        }
        else if (viewMode == 2)  // AO Debug View
        {
            return float4(ao, ao, ao, 1.0);
        }
        return float4(finalColor, 1.0);
    }

    // Vertex Shader
    void VertexShader(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
    {
        texcoord = float2((id == 2) ? 2.0 : 0.0, (id == 1) ? 2.0 : 0.0);
        position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    /*-----------------.
    | :: Techniques :: |
    '-----------------*/

    technique RGIAO
    {
        pass
        {
            VertexShader = VertexShader;
            PixelShader = MainPS;
        }
    }
}
