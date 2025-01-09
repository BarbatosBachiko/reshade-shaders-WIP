/*------------------.
| :: Description :: |
'-------------------/

 __  _______    ___ ___ ___  
 \ \/ /_   _|__/ __/ __| _ \ 
  >  <  | ||___\__ \__ \   /  !!Not Working on DX9!!
 /_/\_\ |_|    |___/___/_|_\ 
                             
    Version 0.6
    Author: Barbatos Bachiko
    License: MIT

    About: Reflections with ray marching.
     
    History:
    (*) Feature (+) Improvement    (x) Bugfix (-) Information (!) Compatibility
    Version 0.6: improve camera
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
        ui_tooltip = "Select the view mode";
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
        ui_min = 0.0;
        ui_max = 1.0;
        ui_step = 0.001;
        ui_reset = 0.1;
    >
    = 0.05;
    uniform float sampleRadius
    <
        ui_category = "Settings";
        ui_type = "slider";
        ui_label = "Sample Radius";
        ui_tooltip = "Adjust the radius of the samples.";
        ui_min = 0.001; ui_max = 5.0; ui_step = 0.001;
    >
    = 0.100;
    uniform int sampleSteps
    <
        ui_category = "Settings";
        ui_type = "slider";
        ui_label = "Sample Steps";
        ui_tooltip = "Adjust the number of steps.";
        ui_min = 1; ui_max = 50; ui_step = 1;
    >
    = 16;
    uniform float jitterIntensity
    <
    ui_category = "Jitter";
    ui_type = "slider";
    ui_label = "Jitter Intensity";
    ui_tooltip = "Adjust the intensity of the jitter effect on reflections.";
    ui_min = 0.0;
    ui_max = 0.1;
    ui_step = 0.001;
    ui_reset = 0.01;
    >
    = 0.01;
    uniform float JitterThreshold
    <
    ui_category = "Jitter";
    ui_type = "slider";
    ui_label = "JitterThreshold";
    ui_tooltip = "Adjust the reflect jitter threshold.";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_reset = 0.1;
    >
    = 0.2;
    uniform float JitterAtenuation
    <
    ui_category = "Jitter";
    ui_type = "slider";
    ui_label = "Jitter Atenuation";
    ui_tooltip = ".";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_reset = 0.5;
    >
    = 0.03;
    uniform int cameraMode
<
    ui_category = "Camera";
    ui_type = "combo";
    ui_label = "Camera Mode";
    ui_tooltip = "Select the camera mode";
    ui_items = 
    "Left + Center + Right\0";
>
= 0; 
    uniform float3 cameraPos1 = float3(1.5, 0.0, -1.0);
    uniform float3 cameraPos2 = float3(1.0, 0.0, 1.0);
    uniform float3 cameraPos3 = float3(-1.5, 10.0, 6.0);
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
    float3 ApplyRayJitter(float3 rayDir, float2 texcoord)
    {
        float2 jitter = frac(sin(float2(dot(texcoord, float2(12.9898, 78.233)),
                                      dot(texcoord, float2(39.346, 11.135)))) * 43758.5453);
        jitter = jitter * 2.0 - 1.0;
        jitter *= jitterIntensity;

        return normalize(rayDir + float3(jitter.x, jitter.y, 0.0));
    }
    float CalculateJitterThreshold(float3 color)
    {
        return dot(color, float3(0.2126, 0.7152, 0.0722));
    }
    float3 ReflectRay(float3 rayDir, float3 normal, float3 color)
    {
        float3 normalizedRayDir = normalize(rayDir);
        float3 normalizedNormal = normalize(normal);
        float dotProduct = dot(normalizedRayDir, normalizedNormal);

        if (abs(dotProduct) < 0.0001)
        {
            dotProduct = 0.0;
        }

        float3 reflectedRay = normalizedRayDir - 2.0 * dotProduct * normalizedNormal;
        float Jitter = CalculateJitterThreshold(color);

        if (Jitter < JitterThreshold)
        {
            reflectedRay *= JitterAtenuation;
        }
        return ApplyRayJitter(reflectedRay, normal.xy);
    }
    float3 RayMarching(float2 texcoord, float3 rayDir, float radius, int steps)
    {
        float3 indirectColor = -2.0;
        float stepSize = radius / float(steps);
        float3 rayOrigin = float3(0.0, 10.0, 0.0);

    [loop]
        for (int i = 1; i <= steps; ++i)
        {
            float3 jitteredRayDir = ApplyRayJitter(rayDir, texcoord);

            float2 sampleCoord = texcoord + jitteredRayDir.xy * (i * stepSize);
            sampleCoord = clamp(sampleCoord, 0.0, 1.0);
            float attenuation = 1.0 / (1.0 + i * stepSize);
            indirectColor += tex2D(BackBuffer, sampleCoord).rgb * attenuation;
        }
        return indirectColor;
    }
    float4 XTSSR(float2 texcoord, float3 cameraPos, float3 reflectionPlaneNormal, float reflectionHeight, float radius)
    {
        float4 originalColor = tex2D(BackBuffer, texcoord);
        float3 indirectColor = float3(0.0, 0.0, 0.0);
        float3 normal = reflectionPlaneNormal;
        normal = normalize(tex2D(BackBuffer, texcoord).rgb * 2.0 - 1.0);
        float3 reflectionRayDir = ReflectRay(cameraPos, normal, originalColor.rgb);
        indirectColor = RayMarching(texcoord, reflectionRayDir, radius, sampleSteps);
        indirectColor *= reflectionIntensity;;
        return float4(originalColor.rgb + indirectColor, 1.0);
    }
    float4 ProcessCamera(float2 texcoord, float3 cameraPos, float3 reflectionPlaneNormal, float reflectionHeight)
    {
        return XTSSR(texcoord, cameraPos, reflectionPlaneNormal, reflectionHeight, sampleRadius);
    }
    float4 CombineCameras(float2 texcoord, float3 reflectionPlaneNormal, float reflectionHeight)
    {
        float4 color1 = ProcessCamera(texcoord, cameraPos1, reflectionPlaneNormal, reflectionHeight);
        float4 color2 = ProcessCamera(texcoord, cameraPos2, reflectionPlaneNormal, reflectionHeight);
        float4 color3 = ProcessCamera(texcoord, cameraPos3, reflectionPlaneNormal, reflectionHeight);
        return (color1 + color2 + color2 + color3) / 3.0;
    }
    float4 XTSSRPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float3 reflectionPlaneNormal = float3(0.0, 1.0, 0.0);
        float reflectionHeight = 0.0;

        float4 finalColor;

        if (cameraMode == 0)
        {
            finalColor = CombineCameras(texcoord, reflectionPlaneNormal, reflectionHeight);
        }
        if (viewMode == 1)
        {
            return float4(finalColor.rgb * reflectionIntensity, 1.0);
        }
        else
        {
            return float4(finalColor.rgb, 1.0);
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
