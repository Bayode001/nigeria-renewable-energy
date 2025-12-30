## Nigeria Renewable Energy Suitability Analysis

Interactive web map visualizing renewable energy potential across Nigerian states.


## Live Demo
[https://bayode001.github.io/nigeria-renewable-energy/](https://bayode001.github.io/nigeria-renewable-energy/)


## Features
- **Solar, Wind, Hydro & Composite** energy suitability analysis
- **37 Nigerian states** with individual scoring
- **Interactive visualization** with color-coded classification
- **State-by-state comparison** of renewable energy potential
- **Custom classification thresholds** for each energy type


## Data Structure
- `index.html` - Main web application
- `data/nigeria_renewable_energy_analysis_v2.geojson` - GeoJSON data with energy 

scores
- **Solar Suitability**: Normalized scores (0-1 scale)
- **Wind Suitability**: Normalized scores (0-1 scale)  
- **Hydro Suitability**: Normalized scores (0-1 scale)
- **Composite Score**: Weighted combination of all energy types
- **Overall Suitability**: Percentage-based ranking

## Classification Categories
| Energy Type | Very Low | Low | Medium | High | Very High |
|-------------|----------|-----|--------|------|-----------|
| **Solar**   | <0.68    | 0.68-0.69 | 0.69-0.71 | 0.71-0.76 | ≥0.76 |
| **Wind**    | <0.1     | 0.1-0.3 | 0.3-0.5 | 0.5-0.7 | ≥0.7 |
| **Hydro**   | <0.17    | 0.17-0.19 | 0.19-0.20 | 0.20-0.21 | ≥0.21 |
| **Overall** | Poor (<10%) | Fair (10-30%) | Moderate (30-50%) | Good (50-70%) | Excellent (≥70%) |

## How to Use
1. **Select Energy Type**: Click on Solar, Wind, Hydro, Composite, or Overall tabs
2. **View State Details**: Click on any state for detailed scores
3. **Compare Energy Types**: See side-by-side comparison in the sidebar
4. **Download Data**: Export analysis results as CSV or GeoJSON

## Technical Details
- **Framework**: Leaflet.js for mapping
- **Visualization**: Chart.js for graphs
- **Data Format**: GeoJSON with custom classification
- **Hosting**: GitHub Pages
- **Responsive Design**: Works on desktop and mobile devices

## Data Sources
- Processed GIS raster analysis
- Custom classification algorithms
- Nigeria administrative boundaries
- Renewable energy potential assessments

## License
This project is available for educational and research purposes.

