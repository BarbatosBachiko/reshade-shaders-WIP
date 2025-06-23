 /*------------------.
| :: Description :: |
'-------------------/

    SSRT_WD

    Version 1.0
    Author: Barbatos Bachiko
    Original SSRT by jebbyk : https://github.com/jebbyk/SSRT-for-reshade/blob/main/ssrt.fx

    License: GNU Affero General Public License v3.0 : https://github.com/jebbyk/SSRT-for-reshade/blob/main/LICENSE
    Aces Tonemapping use Pentalimbed Unlicense: https://github.com/Pentalimbed/YASSGI/blob/main/UNLICENSE

    About: Screen Space Ray Tracing without depth

    History:
    (*) Feature (+) Improvement (x) Bugfix (-) Information (!) Compatibility
    
    Version 1.0
*/

/*-------------------.
| :: Definitions ::  |
'-------------------*/

#include "ReShade.fxh"

// Motion vector configuration+
#ifndef USE_MARTY_LAUNCHPAD_MOTION
#define USE_MARTY_LAUNCHPAD_MOTION 0
#endif

#ifndef USE_VORT_MOTION
#define USE_VORT_MOTION 0
#endif

// Resolution scaling
#ifndef RES_SCALE
#define RES_SCALE 0.8
#endif
#define RES_WIDTH (ReShade::ScreenSize.x * RES_SCALE)
#define RES_HEIGHT (ReShade::ScreenSize.y * RES_SCALE)

// Utility macros
#define GetColor(c) tex2Dlod(ReShade::BackBuffer, float4((c).xy, 0, 0))
#define S_PC MagFilter=POINT;MinFilter=POINT;MipFilter=POINT;AddressU=Clamp;AddressV=Clamp;AddressW=Clamp;

/*-------------------.
| :: Parameters ::   |
'-------------------*/

uniform float IndirectIntensity <
    ui_type = "slider";
    ui_min = 0.1; ui_max = 5.0;
    ui_step = 0.001;
    ui_category = "General";
    ui_label = "GI Intensity";
> = 2.0;

uniform float CONTRAST_THRESHOLD <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 0.1;
    ui_step = 0.001;
    ui_category = "General";
    ui_label = "CONTRAST_THRESHOLD";
> = 0.1;


uniform bool EnableDiffuseGI <
    ui_type = "checkbox";
    ui_category = "General";
    ui_label = "Enable Diffuse GI (BETA)";
> = true;

// Temporal Settings
uniform float AccumFramesDF <
    ui_type = "slider";
    ui_category = "Temporal";
    ui_label = "GI Temporal";
    ui_min = 1.0; ui_max = 32.0; ui_step = 1.0;
> = 12.0;

uniform float FadeStart
    <
        ui_category = "Fade Settings";
        ui_type = "slider";
        ui_label = "Fade Start";
        ui_tooltip = "Distance starts to fade out";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    >
    = 0.0;

uniform float FadeEnd
    <
        ui_category = "Fade Settings";
        ui_type = "slider";
        ui_label = "Fade End";
        ui_tooltip = "Distance completely fades out";
        ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    >
    = 2.0;

uniform int ViewMode <
    ui_type = "combo";
    ui_category = "Debug";
    ui_label = "View Mode";
    ui_items = "None\0Motion\0GI\0Diffuse Light\0";
> = 0;

// Extra Settings
uniform bool AssumeSRGB < 
    ui_category = "Tone Mapping";
    ui_label = "Assume sRGB Input";
> = true;

uniform bool EnableACES <
    ui_category = "Tone Mapping";
    ui_label = "Enable ACES Tone Mapping";
> = false;

uniform float Saturation <
    ui_type = "slider";
    ui_category = "Extra";
    ui_label = "Saturation";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 1.0;

uniform int BlendMode <
    ui_type = "combo";
    ui_category = "Extra";
    ui_label = "Blend Mode";
    ui_items = "Additive\0Multiplicative\0Alpha Blend\0";
> = 1;

uniform int FRAME_COUNT < source = "framecount"; >;
uniform int random < source = "random";min = 0; max = 512; >;


//Ray Marching
static const float MaxTraceDistance = 1.0;
static const float RAYS_AMOUNT = 1.0;
static const int STEPS_PER_RAY = 32;
static const float EnableTemporal = true;
static const float MIN_STEP_SIZE = 0.001;

/*---------------.
| :: Textures :: |
'---------------*/

#if USE_MARTY_LAUNCHPAD_MOTION
    namespace Deferred {
        texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex; };
    }
#elif USE_VORT_MOTION
    texture2D MotVectTexVort { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
    sampler2D sMotVectTexVort { Texture = MotVectTexVort; S_PC };
#else
texture texMotionVectors
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RG16F;
};
sampler sTexMotionVectorsSampler
{
    Texture = texMotionVectors;S_PC
};
#endif

namespace SSRT_WD
{
    texture DiffuseGI
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA16f;
    };
    sampler sDFGI
    {
        Texture = DiffuseGI;
    };
    
    texture DiffuseTemp
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA16f;
    };
    sampler sDiffuseTemp
    {
        Texture = DiffuseTemp;
    };

    texture2D DiffuseHistory
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA16f;
    };
    sampler2D sDFGIHistory
    {
        Texture = DiffuseHistory;
        SRGBTexture = false;
    };
    
/*----------------.
| :: Functions :: |
'----------------*/
    
    //Unlicence Start
    static const float3x3 g_sRGBToACEScg = float3x3(
    0.613117812906440, 0.341181995855625, 0.045787344282337,
    0.069934082307513, 0.918103037508582, 0.011932775530201,
    0.020462992637737, 0.106768663382511, 0.872715910619442
);

    static const float3x3 g_ACEScgToSRGB = float3x3(
    1.704887331049502, -0.624157274479025, -0.080886773895704,
    -0.129520935348888, 1.138399326040076, -0.008779241755018,
    -0.024127059936902, -0.124620612286390, 1.148822109913262
);
    //End

    float lum(float3 color)
    {
        return (color.r + color.g + color.b) * 0.3333333;
    }

    float3 LinearizeSRGB(float3 color)
    {
        return pow(color, 2.2);
    }

    float3 sRGB_to_ACEScg(float3 srgb)
    {
        return mul(g_sRGBToACEScg, srgb);
    }

    float3 ACEScg_to_sRGB(float3 acescg)
    {
        return mul(g_ACEScgToSRGB, acescg);
    }

    // ACES tone mapping approximation (RRT + ODT)
    float3 ApplyACES(float3 color)
    {
        if (!EnableACES)
            return color;
    
        float3 acescg = sRGB_to_ACEScg(color);

        const float A = 2.51;
        const float B = 0.03;
        const float C = 2.43;
        const float D = 0.59;
        const float E = 0.14;

        float3 toneMapped = (acescg * (A * acescg + B)) / (acescg * (C * acescg + D) + E);

        return ACEScg_to_sRGB(toneMapped);
    }

    float3 rand3d(float2 uv)
    {
        uv += random;
        float3 r;
        r.x = frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453) * 2.0 - 1.0;
        r.y = frac(sin(dot(uv, float2(93.9898, 67.345))) * 12741.3427) * 2.0 - 1.0;
        r.z = frac(sin(dot(uv, float2(29.533, 94.729))) * 31415.9265) * 2.0 - 1.0;
        return r;
    }
   
    float3 EstimateNormal(float2 uv)
    {
        float l0 = lum(GetColor(uv).rgb);
        float ldx = lum(GetColor(uv + float2( MIN_STEP_SIZE, 0)).rgb) - l0;
        float ldy = lum(GetColor(uv + float2(0, MIN_STEP_SIZE)).rgb) - l0;
        float3 n = float3(-ldx, -ldy, 1.0);
        return normalize(n);
    }

    float3 EstimateViewDir(float2 uv)
    {
        float3 dir = float3((uv - 0.5) * 2.0, 1.0);
        return normalize(dir);
    }

    float3 TraceColorRay(float2 uv, float3 Raydir)
    {
        float2 currUV = uv;
        float step = MIN_STEP_SIZE;
        float3 accum = float3(0, 0, 0);

        for (int i = 0; i < STEPS_PER_RAY; i++)
        {
            currUV += Raydir.xy * step;
            step = min(step * 1.2, MaxTraceDistance / STEPS_PER_RAY);

            if (any(currUV < 0.0) || any(currUV > 1.0))
                break;

            float3 sampleA = GetColor(currUV).rgb;
            float lumDiff = abs(lum(sampleA) - lum(GetColor(uv).rgb));
            if (lumDiff > CONTRAST_THRESHOLD)
            {
                accum = sampleA;
                return accum; 
            }
        }

        float2 farUV = saturate(uv + Raydir.xy * MaxTraceDistance);
        return GetColor(farUV).rgb * 0.4;
    }

    float4 TraceDiffuseGI(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        if (!EnableDiffuseGI)
            return float4(0, 0, 0, 1);

        float3 accum = float3(0, 0, 0);
        float invRays = 1.0 / RAYS_AMOUNT;
        float fadeRange = max(FadeEnd - FadeStart, 0.001);

    [unroll]
        for (int r = 0; r < RAYS_AMOUNT; ++r)
        {
            float3 n = EstimateNormal(uv);
            float3 noise = rand3d(uv * (r + 1));
            float2 dir2 = normalize(n.xy + noise.xy * 0.1);
            float3 rayDir = float3(dir2, n.z);

            accum += TraceColorRay(uv, rayDir) * invRays * IndirectIntensity;
        }

        float fade = saturate((FadeEnd - length(uv - 0.5)) / fadeRange);
        float3 outCol = saturate(accum * fade / (accum + 1));
        return float4(outCol, 1.0);
    }
    
    float2 GetMotionVector(float2 texcoord)
    {
#if USE_MARTY_LAUNCHPAD_MOTION
        return tex2Dlod(Deferred::sMotionVectorsTex, float4(texcoord, 0, 0)).xy;
#elif USE_VORT_MOTION
        return tex2Dlod(sMotVectTexVort, float4(texcoord, 0, 0)).xy;
#else
        return tex2Dlod(sTexMotionVectorsSampler, float4(texcoord, 0, 0)).xy;
#endif
    }
   
    float4 PS_Temporal(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outSpec : SV_Target1) : SV_Target
    {
        float2 motion = GetMotionVector(uv);

        // Diffuse
        float3 currentGI = tex2Dlod(sDFGI, float4(uv, 0, 0)).rgb;
        float3 historyGI = tex2Dlod(sDFGIHistory, float4(uv + motion, 0, 0)).rgb;
        float3 blendedGI = currentGI;

        if (EnableTemporal && AccumFramesDF > 0 && FRAME_COUNT > 1)
        {
            uint N = min(FRAME_COUNT, (uint) AccumFramesDF);
            blendedGI = (historyGI * (N - 1) + currentGI) / N;
        }
        
        return float4(blendedGI, currentGI.r);
    }

    float4 PS_SaveHistoryDFGI(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float3 gi = EnableTemporal ? tex2Dlod(sDiffuseTemp, float4(uv, 0, 0)).rgb : tex2Dlod(sDFGI, float4(uv, 0, 0)).rgb;
        return float4(gi, 1.0);
    }
    
    float3 HSVtoRGB(float3 c)
    {
        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
    }
    
    float4 Combine(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float4 originalColor = GetColor(texcoord);
        float2 motion = GetMotionVector(texcoord);
    
        // Tex
        float3 diffuseGI = EnableTemporal
        ? tex2Dlod(sDiffuseTemp, float4(texcoord, 0, 0)).rgb 
        : tex2Dlod(sDFGI, float4(texcoord, 0, 0)).rgb;
    
    
        diffuseGI *= IndirectIntensity;
        float3 giColor = diffuseGI;

        // post-processing
        if (AssumeSRGB)
            giColor = LinearizeSRGB(giColor);
        if (EnableACES)
            giColor = ApplyACES(giColor);
    
        float luminance = lum(giColor);
        giColor = lerp(luminance.xxx, giColor, Saturation);

        // Debug visualization
        if (ViewMode != 0)
        {
            switch (ViewMode)
            {
                case 1: // Motion 
                    float velocity = length(motion) * 100.0;
                    float angle = atan2(motion.y, motion.x);
                    float3 hsv = float3((angle / 6.283185) + 0.5, 1.0, saturate(velocity));
                    return float4(HSVtoRGB(hsv), 1.0);
            
                case 2: // Combined GI
                    return float4(giColor, 1.0);
            
                case 3: // Diffuse GI
                    return float4(diffuseGI, 1.0);
            }
            return originalColor;
        }

        switch (BlendMode)
        {
            case 0: // Additive
                return float4(originalColor.rgb + giColor, originalColor.a);
        
            case 1: // Multiplicative
                return float4(1.0 - (1.0 - originalColor.rgb) * (1.0 - giColor), originalColor.a);
        
            case 2: // Alpha Blend
                return float4(lerp(originalColor.rgb, giColor, saturate(giColor.r)), originalColor.a);
        }

        return originalColor;
    }

/*------------------.
| :: Techniques :: |
'------------------*/

    technique SSRT_WD
    {
        pass Diffuse
        {
            VertexShader = PostProcessVS;
            PixelShader = TraceDiffuseGI;
            RenderTarget = DiffuseGI;
        }
        pass Temporal
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Temporal;
            RenderTarget0 = DiffuseTemp;
        }
        pass Save_History_Diffuse
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_SaveHistoryDFGI;
            RenderTarget = DiffuseHistory;
        }
        pass Combine
        {
            VertexShader = PostProcessVS;
            PixelShader = Combine;
        }
    }
}
