using System.Collections.Generic;
using UnityEngine;
using Unity.Mathematics;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    public MetaBallField Field = new MetaBallField();
    
    private MeshFilter _filter;
    private Mesh _mesh;
    
    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    private const float normalD = 0.001f;
    private const float marchingCubeSide = 0.28f;

	private const float SIDE = 4f;
    private const float LEFT = -SIDE;
    private const float DOWN = -SIDE;
    private const float TOP = -SIDE;
    private const float RIGHT = SIDE;
    private const float UP = SIDE;
    private const float BOTTOM = SIDE;
    
    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();
        
        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();
        
        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update()
    {
        List<Vector3> cubeVertices = new List<Vector3>
        {
            new Vector3(0, 0, 0), // 0
            new Vector3(0, 1, 0), // 1
            new Vector3(1, 1, 0), // 2
            new Vector3(1, 0, 0), // 3
            new Vector3(0, 0, 1), // 4
            new Vector3(0, 1, 1), // 5
            new Vector3(1, 1, 1), // 6
            new Vector3(1, 0, 1), // 7
        };

        int[] sourceTriangles =
        {
            0, 1, 2, 2, 3, 0, // front
            3, 2, 6, 6, 7, 3, // right
            7, 6, 5, 5, 4, 7, // back
            0, 4, 5, 5, 1, 0, // left
            0, 3, 7, 7, 4, 0, // bottom
            1, 5, 6, 6, 2, 1, // top
        };

        
        vertices.Clear();
        indices.Clear();
        normals.Clear();
        
        Field.Update();
        // ----------------------------------------------------------------
        // Generate mesh here. Below is a sample code of a cube generation.
        // ----------------------------------------------------------------
        for (float x = LEFT; x < RIGHT; x += marchingCubeSide)
        {
            for (float y = DOWN; y < UP; y += marchingCubeSide)
            {
                for (float z = TOP; z < BOTTOM; z += marchingCubeSide)
                {
                    Vector3 offset = new Vector3(x, y, z);
                    Vector3 scale = new Vector3(marchingCubeSide, marchingCubeSide, marchingCubeSide);

                    // Evaluate case number and F values
                    int caseNumber = 0;
                    int pow2 = 1;
                    List<float> FValue = new List<float>();
                    for (int i = 0; i < cubeVertices.Count; i++)
                    {
                        Vector3 vertexPos = Vector3.Scale(cubeVertices[i], scale) + offset;
                        float value = Field.F(vertexPos);
                        FValue.Add(value);
                        if (value > 0)
                        {
                            caseNumber += pow2;
                        }
                        pow2 *= 2;
                    }
                    
                    int trianglesCount = MarchingCubes.Tables.CaseToTrianglesCount[caseNumber];
                    for (int triangle = 0; triangle < trianglesCount; triangle++)
                    {
                        int3 trinagleEdges = MarchingCubes.Tables.CaseToVertices[caseNumber][triangle];
                        for (int edge = 0; edge < 3; edge++)
                        {
                            int[] vert = MarchingCubes.Tables._cubeEdges[trinagleEdges[edge]];
                            int v0 = vert[0];
                            int v1 = vert[1];

                            // Position interpolation
                            float t = FValue[v1] / (FValue[v1] - FValue[v0]);
                            Vector3 vertexPos = cubeVertices[v0] * t + cubeVertices[v1] * (1 - t);
                            vertexPos = Vector3.Scale(vertexPos, scale) + offset;

                            indices.Add(vertices.Count);
                            vertices.Add(vertexPos);
							normals.Add(getNormal(vertexPos));
                        }
                    }
                }        
            }
        }
        
        
        // Here unity automatically assumes that vertices are points and hence (x, y, z) will be represented as (x, y, z, 1) in homogenous coordinates
        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.SetNormals(normals); // Use _mesh.SetNormals(normals) instead when you calculate them

        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }

    public Vector3 getNormal(Vector3 point)
    {
        Vector3 dx = new Vector3(normalD, 0, 0);
        Vector3 dy = new Vector3(0, normalD, 0);
        Vector3 dz = new Vector3(0, 0, normalD);
        Vector3 Normal = Vector3.Normalize(new Vector3(
            Field.F(point + dx) - Field.F(point - dx),
            Field.F(point + dy) - Field.F(point - dy),
            Field.F(point + dz) - Field.F(point - dz)
        ));
        return -Normal;
    }
}