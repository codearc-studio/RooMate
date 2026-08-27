const menuButton = document.querySelector('.menu-button');
const menu = document.querySelector('.site-menu');

menuButton?.addEventListener('click', () => {
  const isOpen = menu.classList.toggle('open');
  menuButton.setAttribute('aria-expanded', String(isOpen));
});

menu?.addEventListener('click', (event) => {
  if (event.target.closest('a')) {
    menu.classList.remove('open');
    menuButton?.setAttribute('aria-expanded', 'false');
  }
});

document.getElementById('year').textContent = new Date().getFullYear();
