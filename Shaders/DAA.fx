/*------------------.
| :: Description :: |
'-------------------/

    Directional Anti-Aliasing (DAA)
    
    Version 1.0
    Author: Barbatos Bachiko
    License: MIT

    About: Directional Anti-Aliasing (DAA) is an edge-aware anti-aliasing technique 
    that smooths edges by applying directional blurring based on local gradient detection.

    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility

    Version 1.0
    - Motion vectors support is currently incomplete.

*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

    uniform int View_Mode
<
    ui_category = "Anti-Aliasing";
    ui_type = "combo";
    ui_items = "DAA\0Edge Mask\0Gradient Direction\0Motion (dont work)\0";
    ui_label = "View Mode";
    ui_tooltip = "Select normal or debug view output.";
> = 0;
    
    uniform float DirectionalStrength
<
    ui_type = "slider";
    ui_label = "Strength";
    ui_min = 0.0; ui_max = 3.0; ui_step = 0.05;
    ui_category = "Anti-Aliasing";
> = 2.4;
    
    uniform float PixelWidth
<
    ui_type = "slider";
    ui_label = "Pixel Width";
    ui_tooltip = "Pixel width for edge detection.";
    ui_min = 0.5; ui_max = 4.0; ui_step = 0.1;
    ui_category = "Edge Detection";
> = 1.0;

    uniform float EdgeThreshold
<
    ui_type = "slider";
    ui_label = "Edge Threshold";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.01;
    ui_category = "Edge Detection";
> = 2.0;

    uniform float EdgeFalloff
<
    ui_type = "slider";
    ui_label = "Edge Falloff";
    ui_tooltip = "Smooth falloff range for edge detection.";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.01;
    ui_category = "Edge Detection";
> = 2.0;

    uniform bool EnableTemporalAA
<
    ui_category = "Temporal";
    ui_type = "checkbox";
    ui_label = "Temporal";
    ui_tooltip = "Enable temporal anti-aliasing.";
> = false;

    uniform float TemporalAAFactor
<
    ui_category = "Temporal";
    ui_type = "slider";
    ui_label = "Temporal Strength";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_tooltip = "Blend factor between current DAA and history.";
> = 0.2;

/*---------------.
| :: Textures :: |
'---------------*/
    
    texture2D DAATemporal
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };

    texture2D DAAHistory
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };

    sampler2D sDAATemporal
    {
        Texture = DAATemporal;
    };

    sampler2D sDAAHistory
    {
        Texture = DAAHistory;
    };

#if defined(USE_MARTY_LAUNCHPAD_MOTION)
    namespace Deferred {
        texture MotionVectorsTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
        sampler sMotionVectorsTex { Texture = MotionVectorsTex;  };
    }
#elif defined(USE_VORT_MOTION)
        texture2D MotVectTexVort {  Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RG16F; };
        sampler2D sMotVectTexVort { Texture = MotVectTexVort; S_PC  };
#else
    texture texMotionVectors
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RG16F;
    };
    sampler sTexMotionVectorsSampler
    {
        Texture = texMotionVectors;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
        AddressU = Clamp;
        AddressV = Clamp;
        AddressW = Clamp;
    };
#endif

/*----------------.
| :: Functions :: |
'----------------*/

    float GetLuminance(float3 color)
    {
        return dot(color, float3(0.299, 0.587, 0.114));
    }

    // Calculates the gradient using the Scharr operator
    float2 ComputeGradient(float2 texcoord)
    {
        const float2 offset = ReShade::PixelSize.xy * PixelWidth;
    
        float3 colorTL = tex2D(ReShade::BackBuffer, texcoord + float2(-offset.x, -offset.y)).rgb;
        float3 colorT = tex2D(ReShade::BackBuffer, texcoord + float2(0, -offset.y)).rgb;
        float3 colorTR = tex2D(ReShade::BackBuffer, texcoord + float2(offset.x, -offset.y)).rgb;
        float3 colorL = tex2D(ReShade::BackBuffer, texcoord + float2(-offset.x, 0)).rgb;
        float3 colorR = tex2D(ReShade::BackBuffer, texcoord + float2(offset.x, 0)).rgb;
        float3 colorBL = tex2D(ReShade::BackBuffer, texcoord + float2(-offset.x, offset.y)).rgb;
        float3 colorB = tex2D(ReShade::BackBuffer, texcoord + float2(0, offset.y)).rgb;
        float3 colorBR = tex2D(ReShade::BackBuffer, texcoord + float2(offset.x, offset.y)).rgb;

        float lumTL = GetLuminance(colorTL);
        float lumT = GetLuminance(colorT);
        float lumTR = GetLuminance(colorTR);
        float lumL = GetLuminance(colorL);
        float lumR = GetLuminance(colorR);
        float lumBL = GetLuminance(colorBL);
        float lumB = GetLuminance(colorB);
        float lumBR = GetLuminance(colorBR);

        float gx = (-3.0 * lumTL - 10.0 * lumL - 3.0 * lumBL) + (3.0 * lumTR + 10.0 * lumR + 3.0 * lumBR);
        float gy = (-3.0 * lumTL - 10.0 * lumT - 3.0 * lumTR) + (3.0 * lumBL + 10.0 * lumB + 3.0 * lumBR);

        return float2(gx, gy);
    }

    float4 DirectionalAA(float2 texcoord)
    {
        float4 originalColor = tex2D(ReShade::BackBuffer, texcoord);
        float2 gradient = ComputeGradient(texcoord);
        float edgeStrength = length(gradient);
        float weight = smoothstep(EdgeThreshold, EdgeThreshold + EdgeFalloff, edgeStrength);

        // View Modes
        if (View_Mode == 1)
            return float4(weight.xxx, 1.0); // Edge Mask
        else if (View_Mode == 2)
        {
            float2 normGrad = (edgeStrength > 0.0) ? normalize(gradient) : float2(0.0, 0.0);
            float3 debugDir = float3(normGrad.x * 0.5 + 0.5, normGrad.y * 0.5 + 0.5, 0.0);
            return float4(debugDir, 1.0); // Gradient Direction
        }

        if (weight > 0.01)
        {
            float2 blurDir = normalize(float2(-gradient.y, gradient.x));
            float2 blurOffset = blurDir * ReShade::PixelSize.xy * PixelWidth * DirectionalStrength;

            float4 color1 = tex2D(ReShade::BackBuffer, texcoord + blurOffset * 0.5);
            float4 color2 = tex2D(ReShade::BackBuffer, texcoord - blurOffset * 0.5);
            float4 color3 = tex2D(ReShade::BackBuffer, texcoord + blurOffset);
            float4 color4 = tex2D(ReShade::BackBuffer, texcoord - blurOffset);
        
            float4 smoothedColor = (color1 + color2) * 0.4 + (color3 + color4) * 0.1;
            return lerp(originalColor, smoothedColor, weight);
        }
        return originalColor;
    }

    // dont work
    float2 GetMotionVector(float2 texcoord)
    {
#if defined(USE_MARTY_LAUNCHPAD_MOTION)
            return tex2D(Deferred::sMotionVectorsTex, texcoord).xy;
#elif defined(USE_VORT_MOTION)
            return tex2D(sMotVectTexVort, texcoord).xy;
#else
        return tex2D(sTexMotionVectorsSampler, texcoord).xy;
#endif
    }

    float4 PS_TemporalDAA(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float2 motion = GetMotionVector(texcoord);
        
        if (View_Mode == 3)
        {
            return float4(motion * 0.5 + 0.5, 0.0, 1.0);
        }
      
        float4 current = DirectionalAA(texcoord);
        
        float2 reprojectedTexcoord = texcoord + motion * ReShade::PixelSize.xy;
        float4 history = tex2D(sDAAHistory, reprojectedTexcoord);
        
        float factor = EnableTemporalAA ? TemporalAAFactor : 0.0;
        return lerp(current, history, factor);
    }

    // History pass
    float4 PS_SaveHistoryDAA(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float4 temporalResult = tex2D(sDAATemporal, texcoord);
        return temporalResult;
    }

    // Composite pass
    float4 PS_CompositeDAA(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        return tex2D(sDAATemporal, texcoord);
    }


/*-----------------.
| :: Techniques :: |
'-----------------*/

    technique DAA
    {
        pass Temporal 
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_TemporalDAA;
            RenderTarget = DAATemporal;
        }
        pass SaveHistory
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_SaveHistoryDAA;
            RenderTarget = DAAHistory;
        }
        pass Composite
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_CompositeDAA;
        }
    }
