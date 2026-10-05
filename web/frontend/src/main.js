import { createApp } from 'vue';
import ElementPlus from 'element-plus';
import 'element-plus/dist/index.css';
import './styles.css';
import App from './App.vue';
import router from './router';
import { initializeTheme } from './themes/theme';

initializeTheme();
createApp(App).use(ElementPlus).use(router).mount('#app');
