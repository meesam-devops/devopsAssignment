var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();

var appVersion = builder.Configuration["APP_VERSION"] ?? "1.0.0";
var appMessage = builder.Configuration["APP_MESSAGE"]
    ?? "Hello from the DevOps assessment application!";

builder.Services.AddHealthChecks();

var app = builder.Build();

app.Use(async (context, next) =>
{
    var stopwatch = System.Diagnostics.Stopwatch.StartNew();
    try
    {
        await next(context);
    }
    finally
    {
        app.Logger.LogInformation(
            "HTTP {Method} {Path} responded {StatusCode} in {ElapsedMs} ms",
            context.Request.Method,
            context.Request.Path,
            context.Response.StatusCode,
            stopwatch.ElapsedMilliseconds);
    }
});

app.MapGet("/", () => Results.Ok(new
{
    application = "DevOpsAssessment",
    message = appMessage,
    version = appVersion,
    environment = app.Environment.EnvironmentName,
    timestampUtc = DateTimeOffset.UtcNow
}));

app.MapGet("/version", () => Results.Ok(new { version = appVersion }));

// Basic application health only; no external dependencies are checked.
app.MapHealthChecks("/health");

app.Logger.LogInformation("Starting DevOpsAssessment version {Version}", appVersion);
app.Run();
