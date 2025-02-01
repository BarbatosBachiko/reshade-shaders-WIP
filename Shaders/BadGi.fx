/*------------------.
| :: Description :: |
'-------------------/

BadGI
                   
    Author: Barbatos Bachiko
    License: MIT

    About: Simulates indirect light and AO.

    History:
	(*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility
    
    Version 2.2
    +
*/
#include "ReShade.fxh"

#ifndef PI
#define PI 3.14159265358979323846
#endif

namespace ScreenSpaceGIJonsona
{
/*---------------.
| :: Settings :: |
'---------------*/

    uniform int viewMode
< 
    ui_type = "combo";
    ui_label = "View Mode";
    ui_items = "Normal\0IL Debug\0AO Debug\0Depth\0Normals\0";
    ui_category = "Visualization";
> = 0;

    uniform float giIntensity <
        ui_type = "slider";
        ui_label = "IL Strength";
        ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
        ui_category = "IL Settings";
    > = 1.0;

    uniform float sampleRadius <
        ui_type = "slider";
        ui_label = "Sample Radius";
        ui_min = 0.1; ui_max = 5.0; ui_step = 0.01;
        ui_category = "IL Settings";
    > = 1.0;

    uniform int numSamples <
        ui_type = "slider";
        ui_label = "Sample Count";
        ui_min = 4; ui_max = 64; ui_step = 2;
        ui_category = "IL Settings";
    > = 8;

    uniform float diffuseIntensity
    <
        ui_type = "slider";
        ui_label = "Diffuse Intensity";
        ui_tooltip = "Adjust the intensity of diffuse reflections.";
        ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
        ui_category = "IL Settings";
    >
    = 1.0;

    uniform float aoIntensity
    < 
        ui_type = "slider";
        ui_label = "AO Intensity";
        ui_tooltip = "Adjust the intensity of ambient occlusion.";
        ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
        ui_category = "AO Settings";
    >
    = 0.5;
    
    uniform int AOnumSamples <
        ui_type = "slider";
        ui_label = "Sample Count";
        ui_min = 4; ui_max = 64; ui_step = 2;
        ui_category = "AO Settings";
    > = 8;
    
    uniform float aoRadius
    < 
        ui_type = "slider";
        ui_label = "AO Radius";
        ui_tooltip = "Adjust the radius for ambient occlusion sampling.";
        ui_min = 0.001; ui_max = 10.0; ui_step = 0.01;
        ui_category = "AO Settings";
    >
    = 0.05;

    uniform int rayTraceDepth <
        ui_type = "slider";
        ui_label = "Trace Depth";
        ui_min = 1; ui_max = 4; ui_step = 1;
        ui_category = "Ray Tracing";
    > = 1;
    
    uniform float falloffDistance
    <
        ui_type = "slider";
        ui_label = "Falloff Distance";
        ui_tooltip = "Adjust the distance at which indirect light falls off.";
        ui_min = 0.1; ui_max = 10.0; ui_step = 0.1;
        ui_category = "Geral Settings";
    >
    = 10.0;

/*---------------.
| :: Textures :: |
'---------------*/

    texture ColorTex : COLOR;
    
    sampler ColorSampler
    {
        Texture = ColorTex;
        AddressU = CLAMP;
        AddressV = CLAMP;
    };
    
/*----------------.
| :: Functions :: |
'----------------*/

    float GetLinearDepth(float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords);
    }
    
    float3 GetPosition(float2 coords)
    {
        float EyeDepth = GetLinearDepth(coords.xy) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
        return float3((coords.xy * 0.01 - 0.01) * EyeDepth, EyeDepth);
    }

    float3 GetNormalFromDepth(float2 coords)
    {
        float2 texelSize = 1.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        float depthCenter = GetLinearDepth(coords);
        float depthX = GetLinearDepth(coords + float2(texelSize.x, 0.0));
        float depthY = GetLinearDepth(coords + float2(0.0, texelSize.y));
        float3 deltaX = float3(texelSize.x, 0.0, depthX - depthCenter);
        float3 deltaY = float3(0.0, texelSize.y, depthY - depthCenter);
        return normalize(cross(deltaX, deltaY));
    }

    float3 SampleDiffuse(float2 coord)
    {
        return tex2Dlod(ColorSampler, float4(clamp(coord, 0.0, 1.0), 0, 0)).rgb;
    }

    float2 Hammersley(int i, int N)
    {
        float u = float(i) / float(N);
        float v = 0.0;
        for (int bits = i, j = 0; j < 32; j++)
        {
            v += float(bits & 1) * pow(2.0, -float(j + 1));
            bits = bits >> 1;
        }
        return float2(u, v);
    }

    struct Ray
    {
        float3 Origin;
        float3 Direction;
    };
    struct HitRecord
    {
        float3 Point;
        float3 Normal;
        float T;
        bool Hit;
    };
    
    Ray GetRay(float3 origin, float3 direction)
    {
        Ray r;
        r.Origin = origin;
        r.Direction = direction;
        return r;
    }

    bool HitScene(Ray r, inout HitRecord rec)
    {
        const float maxDistance = 25.0;
        float t = 0.0;
        float stepSize = 0.15;
        bool hitFound = false;

    [loop]
        for (int i = 0; i < 32; i++)
        {
            float3 currentPos = r.Origin + r.Direction * t;
            float2 screenPos = (currentPos.xy / currentPos.z) * 0.5 + 0.5;
        
            if (any(saturate(screenPos) != screenPos))
                return false;

            float sceneDepth = GetLinearDepth(screenPos);
            float depthDelta = currentPos.z - sceneDepth;

            if (depthDelta > 0.001)
            {
            // Binary search
                float low = max(t - stepSize, 0.0);
                float high = t;
            [unroll]
                for (int j = 0; j < 4; j++)
                {
                    float mid = (low + high) * 0.5;
                    float3 midPos = r.Origin + r.Direction * mid;
                    float2 midScreen = (midPos.xy / midPos.z) * 0.5 + 0.5;
                    float midDepth = GetLinearDepth(midScreen);
                
                    (midPos.z > midDepth + 0.001) ? high = mid : low = mid;
                }
            
                rec.T = high;
                rec.Point = r.Origin + high * r.Direction;
                rec.Normal = GetNormalFromDepth((rec.Point.xy / rec.Point.z) * 0.5 + 0.5);
                rec.Hit = true;
                return true;
            }
        
        // Adaptive step size
            stepSize *= 1.15;
            t += stepSize;
        
            if (t > maxDistance)
                break;
        }
    
        return false;
    }

    float3 EnergyCompensation(float3 reflectance, float specularStrength)
    {
        float3 energy = 1.0 - (reflectance * specularStrength);
        return 1.0 / max(energy, 0.0001);
    }

    float3 RayColor(Ray r, int maxDepth, float2 texcoord)
    {
        float3 color = float3(1.0, 1.0, 1.0);
        float3 throughput = float3(1.0, 1.0, 1.0);
        Ray currentRay = r;

    [loop]
        for (int depth = 0; depth < maxDepth; depth++)
        {
            HitRecord rec;
            rec.T = 1e6;
            rec.Hit = false;

            if (HitScene(currentRay, rec))
            {
            // Surface properties
                float2 hitUV = (rec.Point.xy / rec.Point.z) * 0.5 + 0.5;
                float3 albedo = SampleDiffuse(hitUV);
                float3 normal = normalize(rec.Normal);
            
            // Material properties
                float3 viewDir = -currentRay.Direction;
                float fresnel = pow(saturate(1.0 - dot(viewDir, normal)), 3.0);
                float specularStrength = saturate(fresnel * 0.5 * 2.0);
            
            // Scattering directions
                float3 diffuseDir = normalize(normal);
                float3 scatterDir = diffuseDir;
            
            // Energy conservation
                float3 reflectance = lerp(float3(0.04, 0.04, 0.04), albedo, specularStrength);
                float3 energyComp = EnergyCompensation(reflectance, specularStrength);
                float3 attenuation = lerp(albedo * (1.0 - specularStrength), reflectance, specularStrength) * energyComp;
            
                throughput *= attenuation * saturate(dot(scatterDir, normal));

            // Prepare next ray
                currentRay.Origin = rec.Point + normal * 0.001;
                currentRay.Direction = normalize(scatterDir);
            }
            else
            {
            // Environmental lighting
                float3 envColor = float3(0.4, 0.6, 1.0) * (1.0 - currentRay.Direction.y) * 2.0;
                envColor += float3(1.0, 0.9, 0.8) *
                pow(saturate(dot(currentRay.Direction,
                    normalize(float3(0.5, 0.3, 0.2)))), 8.0);
            
                color *= throughput * envColor * exp(-rec.T * 0.1);
                break;
            }
            
            if (depth > 2)
            {
                float p = max(throughput.r, max(throughput.g, throughput.b));
                if (p < 0.1)
                    break;
                throughput /= p;
            }
        }

        return color;
    }
    
    float CalculateAmbientOcclusion(float2 texcoord, float3 position, float3 normal)
    {
        float occlusion = 0.0;
        float radiusOverSamples = aoRadius / AOnumSamples;

    [loop]
        for (int i = 0; i < numSamples; ++i)
        {
            float2 sampleDir = Hammersley(i, AOnumSamples);
            sampleDir *= radiusOverSamples;

            float2 sampleCoord = texcoord + sampleDir;
            float3 samplePos = GetPosition(sampleCoord);

            if (GetLinearDepth(sampleCoord) < position.z)
            {
                float3 dirToSample = normalize(samplePos - position);
                float NdotS = max(dot(normal, dirToSample), 0.0);
                float dist = length(samplePos - position);

                float falloff = exp(-dist / falloffDistance);

                occlusion += NdotS * falloff * (1.0 / (1.0 + dist));
            }
        }

        occlusion = 1.0 - (occlusion / numSamples);
        return pow(saturate(occlusion), aoIntensity * 2.0);
    }
    
    float3 CalculateIndirectLight(float2 texcoord, float radius)
    {
        float3 indirect = 0.0;
        float3 viewPos = GetPosition(texcoord);
        float3 normal = GetNormalFromDepth(texcoord);

        float radiusFactor = radius / viewPos.z;

        for (int i = 0; i < numSamples; ++i)
        {
        // Generate sample in cosine-weighted hemisphere around normal
            float2 sampleDir = Hammersley(i, numSamples);
            float3 tangent = normalize(float3(sampleDir.x, sampleDir.y, 0.0) - normal * dot(float3(sampleDir.x, sampleDir.y, 0.0), normal));
            float3 bitangent = cross(normal, tangent);
            float r = sqrt(sampleDir.x);
            float phi = 2.0 * PI * sampleDir.y;
            float x = r * cos(phi);
            float y = r * sin(phi);
            float z = sqrt(1.0 - x * x - y * y);
            float3 sampleDir3D = tangent * x + bitangent * y + normal * z;
        
            sampleDir3D *= radiusFactor;

            Ray giRay = GetRay(viewPos, sampleDir3D);
            float3 rayColor = RayColor(giRay, rayTraceDepth, texcoord);
            float NdotS = max(dot(normal, giRay.Direction), 0.0);

            float distanceToSample = length(viewPos - giRay.Origin);
            float falloff = exp(-distanceToSample / falloffDistance);
            indirect += rayColor * NdotS * falloff * diffuseIntensity;
        }
        indirect *= giIntensity / numSamples;
        indirect *= CalculateAmbientOcclusion(texcoord, viewPos, normal);

        return indirect;
    }

    float4 GI_Pass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float3 originalColor = SampleDiffuse(texcoord);
        float3 indirectLight = CalculateIndirectLight(texcoord, sampleRadius);

        float3 finalColor = originalColor + giIntensity * indirectLight * 1.5;

        if (viewMode == 0)
        {
            return float4(finalColor, 1.0);
        }
        else if (viewMode == 1)
        {
            return float4(indirectLight, 1.0);
        }
        else if (viewMode == 3)
        {
            float depth = GetLinearDepth(texcoord);
            return float4(depth, depth, depth, 1.0);
        }
        else if (viewMode == 4)
        {
            float3 normal = GetNormalFromDepth(texcoord);
            return float4(normal * 0.5 + 0.5, 1.0);
        }
        return float4(originalColor, 1.0);
    }
    
    float4 AO_Pass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float3 originalColor = SampleDiffuse(texcoord);
        float3 position = GetPosition(texcoord);
        float3 normal = GetNormalFromDepth(texcoord);

        float ao = CalculateAmbientOcclusion(texcoord, position, normal);
        float3 finalColor = originalColor * ao;

        if (viewMode == 0)
        {
            return float4(finalColor, 1.0);
        }
        else if (viewMode == 2)
        {
            return float4(ao, ao, ao, 1.0); // Debug AO
        }
        return float4(originalColor, 1.0);
    }
    
    void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
    {
        texcoord = float2((id == 2) ? 2.0 : 0.0, (id == 1) ? 2.0 : 0.0);
        position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

/*-----------------.
| :: Techniques :: |
'-----------------*/

    technique BadGI
    {
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = GI_Pass;
        }
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = AO_Pass;
        }
    }
}
