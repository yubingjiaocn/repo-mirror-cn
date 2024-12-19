import aiohttp
import asyncio
import logging
from typing import List, Dict

PYPI_URL = "https://pypi.org/simple"
PYPI_JSON_URL = "https://pypi.org/pypi"

PACKAGE_LIST_URL = "https://cdn.jsdelivr.net/gh/hugovk/top-pypi-packages/top-pypi-packages-30-days.min.json"
CONCURRENCY = 5

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PyPiPackageFetcher:
    def __init__(self, concurrent_downloads: int = 5):
        self.concurrent_downloads = concurrent_downloads

    async def fetch_package_list(self, session: aiohttp.ClientSession) -> List[Dict]:
        """Fetch list of top PyPI packages"""
        try:
            logger.info("Fetching package list from hugovk.github.io...")
            async with session.get(PACKAGE_LIST_URL) as response:
                if response.status == 200:
                    try:
                        data = await response.json()
                        # Take first 10 packages from the rows array
                        packages = [{"name": pkg["project"]} for pkg in data["rows"]]
                        logger.info(f"Retrieved {len(packages)} packages")
                        return packages
                    except Exception as e:
                        logger.error(f"Error parsing JSON: {e}")
                        return []
                else:
                    logger.error(f"Failed to fetch package list: {response.status}")
                    return []

        except Exception as e:
            logger.error(f"Error fetching package list: {e}")
            return []

    async def download_package(self, session: aiohttp.ClientSession, package: Dict) -> None:
        """Download a wheel file for a PyPI package"""
        name = package["name"]
        json_url = f"{PYPI_JSON_URL}/{name}/json"

        try:
            # First get package metadata to find wheel files
            logger.info(f"Fetching metadata for {name}")
            async with session.get(json_url) as response:
                if response.status == 200:
                    data = await response.json()
                    releases = data.get("releases", {})
                    latest_version = data["info"]["version"]

                    # Look for wheel files in the latest version
                    wheel_files = [
                        f for f in releases.get(latest_version, [])
                        if f["filename"].endswith(".whl")
                    ]

                    if wheel_files:
                        # Download the first available wheel file
                        wheel_url = wheel_files[0]["url"]
                        logger.info(f"Downloading wheel for {name}: {wheel_url}")
                        async with session.get(wheel_url) as wheel_response:
                            if wheel_response.status == 200:
                                await wheel_response.read()  # Read to warm up the mirror
                                logger.info(f"Downloaded wheel for {name}")
                            else:
                                logger.error(f"Failed to download wheel for {name}: {wheel_response.status}")
                    else:
                        logger.warning(f"No wheel files found for {name} {latest_version}")
                        # Fallback to simple API
                        package_url = f"{PYPI_URL}/{name}/"
                        async with session.get(package_url) as simple_response:
                            if simple_response.status == 200:
                                await simple_response.read()
                                logger.info(f"Downloaded simple index for {name} (no wheel available)")
                            else:
                                logger.error(f"Failed to download simple index for {name}: {simple_response.status}")
                else:
                    logger.error(f"Failed to fetch metadata for {name}: {response.status}")
        except Exception as e:
            logger.error(f"Error processing {name}: {e}")

    async def run(self) -> None:
        """Main execution method"""
        async with aiohttp.ClientSession() as session:
            logger.info("Fetching package list...")
            packages = await self.fetch_package_list(session)

            if packages:
                logger.info(f"Found {len(packages)} packages. Starting downloads...")
                tasks = [
                    asyncio.create_task(self.download_package(session, package))
                    for package in packages
                ]

                # Process in batches to limit concurrency
                for i in range(0, len(tasks), self.concurrent_downloads):
                    batch = tasks[i:i + self.concurrent_downloads]
                    await asyncio.gather(*batch)

                logger.info("All packages processed")
            else:
                logger.error("No packages found")

async def main():
    fetcher = PyPiPackageFetcher(concurrent_downloads=CONCURRENCY)
    await fetcher.run()

if __name__ == "__main__":
    asyncio.run(main())
