/*------------------.
| :: Description :: |
'-------------------/

   Fog Atmospheric Shader

   Author: Barbatos Bachiko
   License: MIT
   Purpose: Ideal for adding atmospheric depth to scenes, simulating weather conditions, or enhancing visual aesthetics.
            
   Features:
   - Configurable fog intensity, start, and end distances
   - Supports small depth ranges for tightly packed depth buffers
   - User-defined fog color for customizable effects

*/

    /*---------------.
    | :: Settings :: |
    '---------------*/

    uniform float FogStrength < 
        ui_type = "slider";
        ui_label = "Fog Strength"; 
        ui_tooltip = "Controls the intensity of the fog effect."; 
        ui_min = 0.0; 
        ui_max = 1.0; 
        ui_default = 0.5; 
    > = 0.5;

    uniform float FogStart < 
        ui_type = "slider";
        ui_label = "Fog Start"; 
        ui_tooltip = "Depth value where fog starts (use small values for tight depth ranges)."; 
        ui_min = 0.0; 
        ui_max = 0.01; 
        ui_default = 0.010; 
    > = 0.010;

    uniform float FogEnd < 
        ui_type = "slider";
        ui_label = "Fog End"; 
        ui_tooltip = "Depth value where fog is fully opaque (use small values for tight depth ranges)."; 
        ui_min = 0.0; 
        ui_max = 0.01; 
        ui_default = 0.000; 
    > = 0.000;

    uniform float3 FogColor < 
        ui_type = "color";
        ui_label = "Fog Color"; 
        ui_tooltip = "The color of the fog."; 
    > = float3(0.5, 0.5, 0.5);

    /*---------------.
    | :: Textures :: |
    '---------------*/
namespace Shader
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

    // Loads color from the color texture
    float4 LoadColor(float2 texcoord)
    {
        return tex2D(ColorSampler, texcoord);
    }

    // Loads depth from the depth texture
    float LoadDepth(float2 texcoord)
    {
        return tex2D(DepthSampler, texcoord).r;
    }

    // Calculates fog intensity based on depth
    float FogFactor(float depth)
    {
        return saturate((depth - FogStart) / (FogEnd - FogStart));
    }

    // Applies the fog effect
    float4 ApplyFog(float4 color, float depth)
    {
        float fogIntensity = FogFactor(depth) * FogStrength;
        float3 foggedColor = lerp(color.rgb, FogColor, fogIntensity);
        return float4(foggedColor, color.a);
    }

    // PixelShader
    float4 Out(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float depth = LoadDepth(texcoord); // Retrieve depth value
        float4 color = LoadColor(texcoord); // Retrieve color

        return ApplyFog(color, depth);
    }

    // Vertex shader
    void CustomPostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
    {
        texcoord = float2((id == 2) ? 2.0 : 0.0, (id == 1) ? 2.0 : 0.0);
        position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    /*-----------------.
    | :: Techniques :: |
    '-----------------*/

    technique FogEffect
    {
        pass
        {
            VertexShader = CustomPostProcessVS;
            PixelShader = Out;
        }
    }
}
