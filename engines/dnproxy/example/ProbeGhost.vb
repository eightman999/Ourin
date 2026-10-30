Imports System
Imports Microsoft.VisualBasic
Imports System.IO
Imports System.Runtime.InteropServices
Imports System.Text
Imports D.N
Imports Ukagaka.NET.Interfaces

Namespace Ourin.DnProxyVB
    Public Class ProbeGhost
        Inherits MarshalByRefObject
        Implements IShiori30
        Private root As String = ""
        Private boots As Integer
        Public Function load(input As IntPtr, length As Integer) As Boolean Implements ILoad.load
            Try
                root = Marshal.PtrToStringAnsi(input, length)
            Finally
                Marshal.FreeHGlobal(input)
            End Try
            If File.Exists(Path.Combine(root, "vb-save.txt")) Then boots = Integer.Parse(File.ReadAllText(Path.Combine(root, "vb-save.txt")))
            Logger.LogType = 2
            Logger.LogLevel = Logger.Level.ALL
            Logger.LogCharset = Logger.Charset.UTF8
            Logger.Initialize(root)
            Logger.WriteLine(Logger.Level.INFO, "VB load: 桜鈴")
            Return True
        End Function
        Public Function unload() As Boolean Implements IUnload.unload
            File.WriteAllText(Path.Combine(root, "vb-save.txt"), boots.ToString())
            Logger.WriteLine(Logger.Level.INFO, "VB unload: 桜鈴")
            Logger.Finalize()
            Return True
        End Function
        Public Overloads Function request(wire As String) As String
            Dim headers As New Collections.Generic.Dictionary(Of String, String)
            For Each line As String In wire.Split(New String() {vbCrLf}, StringSplitOptions.None)
                Dim colon As Integer = line.IndexOf(": ")
                If colon >= 0 Then headers(line.Substring(0, colon)) = line.Substring(colon + 2)
            Next
            Dim value As String = Nothing
            If Not wire.StartsWith("NOTIFY ") AndAlso headers.ContainsKey("ID") Then
                Select Case headers("ID")
                    Case "version"
                        value = "VB/real-Roslyn"
                    Case "OnBoot"
                        boots += 1
                        value = "桜鈴 🌸 " & boots.ToString()
                    Case "OnEcho"
                        value = headers("Reference0")
                    Case "OnClose"
                        value = "終了します。"
                End Select
            End If
            If value Is Nothing Then Return "SHIORI/3.0 204 No Content" & vbCrLf & "Charset: UTF-8" & vbCrLf & vbCrLf
            Return "SHIORI/3.0 200 OK" & vbCrLf & "Charset: UTF-8" & vbCrLf & "Value: " & value & vbCrLf & vbCrLf
        End Function
        Public Overloads Function request(input As IntPtr, ByRef length As Integer) As IntPtr Implements IRequest.request
            Dim wire As String
            Try
                wire = Marshal.PtrToStringAnsi(input, length)
            Finally
                Marshal.FreeHGlobal(input)
            End Try
            Dim response As String = request(wire)
            length = Encoding.UTF8.GetByteCount(response)
            Return Marshal.StringToHGlobalAnsi(response)
        End Function
    End Class
End Namespace
