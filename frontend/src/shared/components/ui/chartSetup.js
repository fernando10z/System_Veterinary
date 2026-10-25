import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  ArcElement,
  Filler
} from "chart.js";

ChartJS.register(
  CategoryScale, LinearScale, BarElement, PointElement, LineElement,
  Title, Tooltip, Legend, ArcElement, Filler
);

ChartJS.defaults.font.family =
  "'IBM Plex Sans', ui-sans-serif, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";
ChartJS.defaults.font.size = 11.5;
ChartJS.defaults.color = "#6A7F76";
ChartJS.defaults.borderColor = "#E5EBE6";

// Series de la paleta: la 1 es el dato principal, la 2 la comparación.
export const SERIES = ["#178A72", "#5FC4AA"];
