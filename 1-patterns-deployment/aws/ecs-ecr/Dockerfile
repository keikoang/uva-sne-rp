FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/ConnectivityCheck.csproj ./src/
RUN dotnet restore ./src/ConnectivityCheck.csproj
COPY src/ ./src/
RUN dotnet publish ./src/ConnectivityCheck.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    dnsutils \
    traceroute \
    nmap \
    iputils-ping \
    iproute2 \
    awscli \
    && rm -rf /var/lib/apt/lists/*

ENV PORT=8080
ENV ASPNETCORE_URLS=http://+:8080
ENV DOTNET_RUNNING_IN_CONTAINER=true
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "ConnectivityCheck.dll"]