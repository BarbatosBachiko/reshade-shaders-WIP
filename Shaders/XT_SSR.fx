/*------------------.
| :: Description :: |
'-------------------/

 __  _______    ___ ___ ___  
 \ \/ /_   _|__/ __/ __| _ \ 
  >  <  | ||___\__ \__ \   /  !!Not Working on DX9!!
 /_/\_\ |_|    |___/___/_|_\ 
                             

    Version 0.3
    Author: Barbatos Bachiko
    License: MIT

    About: Reflections with ray marching.
     
    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility
*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

namespace XT_SSR 
{
    /*---------------.
    | :: Settings :: |
    '---------------*/

    uniform int viewMode
    <
        ui_category = "Settings";
        ui_type = "combo";
        ui_label = "View Mode";
        ui_tooltip = "Select the view mode for RMGI";
        ui_items = 
    "Normal\0" 
    "Reflection Debug\0"
    "Depth Debug\0";
    >
    = 0;

    uniform float reflectionIntensity
    <
        ui_category = "Settings";
        ui_type = "slider";
        ui_label = "Reflection Intensity";
        ui_tooltip = "Adjust the intensity.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
        ui_reset = 0.02;
    >
    = 0.02;

    uniform float sampleRadius
    <
        ui_category = "Settings";
        ui_type = "slider";
        ui_label = "Sample Radius";
        ui_tooltip = "Adjust the radius of the samples.";
        ui_min = 0.001; ui_max = 5.0; ui_step = 0.001;
    >
    = 0.005;

    uniform int sampleSteps
    <
        ui_category = "Settings";
        ui_type = "slider";
        ui_label = "Sample Steps";
        ui_tooltip = "Adjust the number of steps for ray marching.";
        ui_min = 1; ui_max = 50; ui_step = 1;
    >
    = 16;

    uniform bool useNormals
    <
        ui_category = "Settings";
        ui_type = "checkbox";
        ui_label = "Use Normals";
        ui_tooltip = "Toggle whether the shader uses normal textures for reflections.";
    >
    = true;

    uniform float3 lightPosition
    <
        ui_category = "Light";
        ui_type = "vector";
        ui_label = "Light Position";
        ui_tooltip = "Position of the light source.";
    >
    = float3(1.0, 10.0, 0.0);

    uniform float3 lightColor
    <
        ui_category = "Light";
        ui_type = "color";
        ui_label = "Light Color";
        ui_tooltip = "Color of the light.";
    >
    = float3(1.0, 1.0, 1.0);

    uniform float lightIntensity
    <
        ui_category = "Light";
        ui_type = "slider";
        ui_label = "Light Intensity";
        ui_tooltip = "Adjust the intensity of the light.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    >
    = 0.2;

    /*---------------.
    | :: Textures :: |
    '---------------*/

    texture2D BackBufferTex : COLOR;
    sampler2D BackBuffer
    {
        MinFilter = Linear;
        MagFilter = Linear;
        AddressU = Clamp;
        AddressV = Clamp;
        Texture = BackBufferTex;
    };

    /*----------------.
    | :: Functions :: |
    '----------------*/

    float SampleDepth(float2 coord)
    {
        float texDepth = tex2D(BackBuffer, clamp(coord, 0.0, 1.0)).r;
        float linearDepth = ReShade::GetLinearizedDepth(coord);

        return lerp(texDepth, linearDepth, 0.5);
    }

    float3 ReflectRay(float3 rayDir, float3 normal)
    {
        float3 normalizedNormal = normalize(normal);
        float dotProduct = dot(rayDir, normalizedNormal);
        return rayDir - 2.0 * dotProduct * normalizedNormal;
    }

    bool RayIntersectsPlane(float3 rayOrigin, float3 rayDir, float3 planePoint, float3 planeNormal, out float t)
    {
        float denom = dot(rayDir, planeNormal);
        if (abs(denom) > 0.0001)
        {
            float3 p0l0 = planePoint - rayOrigin;
            t = dot(p0l0, planeNormal) / denom;
            return (t >= 0.0);
        }
        t = 0.0;
        return false;
    }

    float3 RayMarching(float2 texcoord, float3 rayDir, float radius, int steps)
    {
        float3 indirectColor = 0.0;
        float stepSize = radius / float(steps);
        float3 rayOrigin = float3(0.0, 10.0, 0.0);

    [loop]
        for (int i = 1; i <= steps; ++i)
        {
            float2 sampleCoord = texcoord + rayDir.xy * (i * stepSize);
            sampleCoord = clamp(sampleCoord, 0.0, 1.0);
            float attenuation = 1.0 / (1.0 + i * stepSize);
            indirectColor += tex2D(BackBuffer, sampleCoord).rgb * attenuation;

            float t;
            if (RayIntersectsPlane(rayOrigin, rayDir, float3(0.0, 0.0, 0.0), float3(0.0, 1.0, 0.0), t))
            {
                indirectColor += tex2D(BackBuffer, sampleCoord).rgb;
            }
        }

        return indirectColor;
    }

    float3 LambertianDiffuse(float3 normal, float3 lightDir)
    {
        float diff = max(dot(normal, lightDir), 0.0);
        return diff * lightColor * lightIntensity;
    }

    float4 XTSSR(float2 texcoord, float3 cameraPos, float3 reflectionPlaneNormal, float reflectionHeight, float radius)
    {
        float4 originalColor = tex2D(BackBuffer, texcoord);
        float3 indirectColor = float3(0.0, 0.0, 0.0);
        float3 normal = reflectionPlaneNormal;

        if (useNormals)
        {
            normal = normalize(tex2D(BackBuffer, texcoord).rgb * 2.0 - 1.0);
        }

        float3 reflectionRayDir = ReflectRay(cameraPos, normal);
        indirectColor = RayMarching(texcoord, reflectionRayDir, radius, sampleSteps);
        indirectColor *= reflectionIntensity;

        float3 lightDir = normalize(lightPosition - cameraPos);
        float3 diffuse = LambertianDiffuse(normal, lightDir);
    
        return float4(originalColor.rgb + indirectColor + diffuse, 1.0);
    }

    float4 XTSSRPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float3 cameraPos = float3(0.0, 10.0, 0.0);
        float3 reflectionPlaneNormal = float3(0.0, 1.0, 0.0);
        float reflectionHeight = 0.0;
        float4 planarReflectionColor = XTSSR(texcoord, cameraPos, reflectionPlaneNormal, reflectionHeight, sampleRadius);

        if (viewMode == 1) 
        {
            
            return float4(planarReflectionColor.rgb * reflectionIntensity, 1.0);
        }
        else if (viewMode == 2) 
        {
            float depth = SampleDepth(texcoord);
            return float4(depth, depth, depth, 1.0);
        }
        else 
        {
            return float4(planarReflectionColor.rgb * 1.0, 1.0); 
        }
    }

    /*-----------------.
    | :: Techniques :: |
    '-----------------*/

    technique XT_SSR 
    {
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = XTSSRPS;
        }
    }
}
