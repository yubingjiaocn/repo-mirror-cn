import aiohttp
import asyncio
import logging
from typing import List, Dict

REGISTRY_URL = "https://registry.npmjs.org"
CONCURRENCY = 5

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NpmPackageFetcher:
    def __init__(self, concurrent_downloads: int = 5):
        self.concurrent_downloads = concurrent_downloads

    async def fetch_package_list(self, session: aiohttp.ClientSession) -> List[Dict]:
        """Fetch list of high-impact packages from jsdelivr CDN"""
        url = "https://cdn.jsdelivr.net/npm/npm-high-impact/lib/top.js"

        try:
            logger.info("Fetching package list from jsdelivr...")
            async with session.get(url) as response:
                if response.status == 200:
                    content = await response.text()
                    # Parse the JavaScript array into Python list
                    package_names = [
                        name.strip().strip("'").strip('"')
                        for name in content.split('[')[1].split(']')[0].split(',')
                        if name.strip()
                    ]

                    # Convert to package objects
                    packages = [{"name": name} for name in package_names]
                    logger.info(f"Retrieved {len(packages)} packages")
                    return packages
                else:
                    logger.error(f"Failed to fetch package list: {response.status}")
                    return []

        except Exception as e:
            logger.error(f"Error fetching package list: {e}")
            return []

    async def download_package(self, session: aiohttp.ClientSession, package: Dict) -> None:
        """Download a single npm package"""
        name = package["name"]
        tarball_url = f"{REGISTRY_URL}/{name}/-/{name}-latest.tgz"

        try:
            logger.info(f"Downloading {name}")
            async with session.get(tarball_url) as response:
                if response.status == 200:
                    await response.read()  # Just read to warm up the mirror
                    logger.info(f"Downloaded {name}")
                else:
                    logger.error(f"Failed to download {name}: {response.status}")
        except Exception as e:
            logger.error(f"Error downloading {name}: {e}")

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
    fetcher = NpmPackageFetcher(concurrent_downloads=CONCURRENCY)
    await fetcher.run()

if __name__ == "__main__":
    asyncio.run(main())
