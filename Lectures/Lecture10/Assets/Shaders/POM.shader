Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        // these three vectors will hold a 3x3 rotation matrix
        // that transforms from tangent to world space
        half3 tspace0 : TEXCOORD1; // tangent.x, bitangent.x, normal.x
        half3 tspace1 : TEXCOORD2; // tangent.y, bitangent.y, normal.y
        half3 tspace2 : TEXCOORD3; // tangent.z, bitangent.z, normal.z
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        o.worldSurfaceNormal = normal;
        
        // compute bitangent from cross product of normal and tangent and output it
        half tangentSign = tangent.w * unity_WorldTransformParams.w;
        half3 wBitangent = cross(wNormal, wTangent) * tangentSign;
        // output the tangent space matrix
        o.tspace0 = half3(wTangent.x, wBitangent.x, wNormal.x);
        o.tspace1 = half3(wTangent.y, wBitangent.y, wNormal.y);
        o.tspace2 = half3(wTangent.z, wBitangent.z, wNormal.z);
        
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    float sampleHeight(float2 uv, float maxHeight)
    {
        return tex2Dlod(_HeightMap, float4(uv, 0, 0)).r * maxHeight;
    }
    
    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
#if MODE_BUMP
        // Change UV according to the Parallax Offset Mapping
        float toph = (1 - tex2D(_HeightMap, uv).r) * _MaxHeight;
        float3 v;
        v.x = dot(i.tspace0, worldViewDir);
        v.y = dot(i.tspace1, worldViewDir);
        v.z = dot(i.tspace2, worldViewDir);
        v = normalize(v);

        float2 duv = toph * (v.xy / v.z);
        uv = uv + duv;
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS
        // Change UV according to Parallax Occclusion Mapping
        float2 oldUV = uv;
        float3 v;
        v.x = dot(i.tspace0, worldViewDir);
        v.y = dot(i.tspace1, worldViewDir);
        v.z = dot(i.tspace2, worldViewDir);
        v = normalize(v);

        float3 curShift = float3(0, 0, 0);
        float curTexHeight = tex2D(_HeightMap, uv).r * _MaxHeight;
        for (int curStep = 0; curStep < _MaxStepCount && curTexHeight <= _MaxHeight - curShift.z; curStep++)
        {
            curShift += _StepLength * v;
            curTexHeight = tex2Dlod(_HeightMap, float4(uv - curShift.xy, 0, 0)).r * _MaxHeight;
        }

        if (curTexHeight > _MaxHeight - curShift.z)
        {
            float3 lastShift = curShift - _StepLength * v;
            float lastTexHeight = tex2Dlod(_HeightMap, float4(uv - lastShift.xy, 0, 0)).r * _MaxHeight;
            float3 lastPos = float3(uv - lastShift.xy, _MaxHeight - lastShift.z);
            float3 curPos = float3(uv - curShift.xy, _MaxHeight - curShift.z);
            float lastDh = lastPos.z - lastTexHeight;
            float curDh = curTexHeight - curPos.z;
            float t = lastDh / (lastDh + curDh);
            uv = lerp(lastPos.xy, curPos.xy, t);
        } else
        {
            // offset mapping
            float toph = (1 - tex2D(_HeightMap, uv).r) * _MaxHeight;
            float2 duv = toph * (v.xy / v.z);
            uv = uv - duv;
        }
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        // Calculate soft shadows according to Parallax Occclusion Mapping, assign to shadow
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        // Implement Normal Mapping
        float3 tnormal = UnpackNormal(tex2D(_NormalMap, uv));
        half3 worldNormal;
        worldNormal.x = dot(i.tspace0, tnormal);
        worldNormal.y = dot(i.tspace1, tnormal);
        worldNormal.z = dot(i.tspace2, tnormal);
        worldNormal = normalize(worldNormal);

        normal = worldNormal;
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));        
        
        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z));
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}