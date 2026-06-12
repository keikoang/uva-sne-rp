var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddConsole();

var app = builder.Build();

var startedAt = DateTimeOffset.UtcNow;

var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME")
                  ?? "container-registry-connectivity-check";

var provider = Environment.GetEnvironmentVariable("CLOUD_PROVIDER")
               ?? "unknown";

var region = Environment.GetEnvironmentVariable("AWS_REGION")
             ?? Environment.GetEnvironmentVariable("AZURE_REGION")
             ?? "unknown";

app.MapGet("/", () => Results.Json(new
{
    service = serviceName,
    provider,
    status = "running",
    meaning = "If this container is running, the platform successfully pulled the image from the private container registry and started the workload.",
    region,
    startedAtUtc = startedAt,
    endpoints = new[] { "/health" }
}));

app.MapGet("/health", () => Results.Json(new
{
    status = "healthy",
    checkedAtUtc = DateTimeOffset.UtcNow
}));

var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";

app.Run($"http://0.0.0.0:{port}");
